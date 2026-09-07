#!/usr/bin/env python3
"""Read-only aspect-change detector. Python standard library + FFmpeg."""
import argparse
from collections import Counter
from datetime import datetime
import html
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import sys


def run(cmd):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode:
        raise RuntimeError(p.stderr[-6000:])
    return p.stdout


def parse_metadata(text):
    """Parse metadata printer records, never cropdetect's diagnostic stderr.

    Frame numbers may restart on resolution changes; pts_time remains the clock.
    Missing/malformed records fail explicitly instead of silently returning no ads.
    """
    records, current = [], None
    def finish():
        if current is not None:
            keys = ('w', 'h', 'x', 'y')
            if not all(k in current for k in keys):
                raise ValueError('crop metadata 缺少字段，详见 metadata.txt')
            crop = tuple(int(current[k]) for k in keys)
            t = current['time']
            if not math.isfinite(t):
                raise ValueError('无效 metadata 时间戳')
            records.append({'time': t, 'crop': crop if crop[0] > 0 and crop[1] > 0 and min(crop[2:]) >= 0 else None})
    for line in text.splitlines():
        if line.startswith('frame:'):
            finish()
            fields = dict(re.findall(r'(\w+):\s*([^\s]+)', line))
            if 'pts_time' not in fields:
                raise ValueError('metadata header 缺少 pts_time；不使用 stderr 日志回退')
            current = {'time': float(fields['pts_time'])}
        elif line.startswith('lavfi.cropdetect.') and current is not None:
            key, value = line.split('=', 1)
            current[key.rsplit('.', 1)[1]] = value
    finish()
    if not records:
        raise ValueError('没有 crop metadata；请检查 FFmpeg filter 支持及 metadata.txt')
    return sorted({r['time']: r for r in records}.values(), key=lambda r: r['time'])


def close(a, b, tolerance):
    return max(abs(x-y) for x, y in zip(a, b)) <= tolerance


def dominant(crops, tolerance):
    counts = Counter(crops)
    # Densest tolerance neighborhood avoids quantization-bin boundaries.
    seed = max(counts, key=lambda a: sum(n for b, n in counts.items() if close(a, b, tolerance)))
    members = [c for c in crops if close(c, seed, tolerance)]
    return tuple(round(statistics.median(c[i] for c in members)) for i in range(4)), len(members)/len(crops)


def detect(samples, duration, interval, tolerance=8, ratio=.12, min_duration=8, gap=2):
    valid = [s['crop'] for s in samples if s['crop']]
    if not valid:
        raise ValueError('所有采样均为黑帧或无效 crop')
    main, support = dominant(valid, tolerance)
    def abnormal(c):
        return c is not None and any(abs(c[i]-main[i]) > max(tolerance, main[i]*ratio) for i in (0, 1))
    runs = []
    for s in samples:
        if not abnormal(s['crop']):
            continue
        t = s['time']
        if runs and t-runs[-1]['last'] <= interval*1.5:
            runs[-1]['last'] = t
            runs[-1]['crops'].append(s['crop'])
        else:
            runs.append({'start': max(0,t-interval/2), 'last': t, 'crops': [s['crop']]})
    # Require real uninterrupted evidence before merging short intervening gaps.
    runs = [dict(r, end=min(duration,r['last']+interval/2)) for r in runs
            if min(duration,r['last']+interval/2)-r['start'] >= min_duration]
    merged = []
    for r in runs:
        if merged and r['start']-merged[-1]['end'] <= gap:
            merged[-1]['end'] = r['end']
            merged[-1]['crops'] += r['crops']
        else:
            merged.append(r)
    candidates = []
    for r in merged:
        crop, stability = dominant(r['crops'], tolerance)
        edge = r['start'] < 30 or r['end'] > duration-30
        high = support >= .6 and stability >= .8 and not edge
        candidates.append({'start': r['start'], 'end': r['end'], 'duration': r['end']-r['start'],
                           'crop': crop, 'confidence': '高' if high else '中',
                           'reason': '持续画幅变化（片头/片尾需额外核对）' if edge else '持续画幅变化',
                           'stability': stability})
    return main, support, candidates


def timestamp(t):
    ms = round(t*1000)
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}.{ms%1000:03}'


def croptext(c):
    return f'{c[0]}x{c[1]}, x={c[2]}, y={c[3]}'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('movie', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--interval', type=float, default=.5)
    p.add_argument('--min-duration', type=float, default=8)
    p.add_argument('--merge-gap', type=float, default=2)
    p.add_argument('--height-ratio', type=float, default=.12, help='宽或高相对变化阈值，默认 0.12')
    p.add_argument('--tolerance', type=int, default=8)
    p.add_argument('--black-limit', type=float, default=.094)
    p.add_argument('--no-previews', action='store_true')
    a = p.parse_args()
    if not all(math.isfinite(x) for x in (a.interval,a.min_duration,a.merge_gap,a.height_ratio,a.black_limit)) or min(a.interval,a.min_duration,a.height_ratio) <= 0 or a.merge_gap < 0 or a.tolerance < 0 or not 0 <= a.black_limit <= 1:
        p.error('参数超出有效范围')
    movie = a.movie.expanduser().resolve(strict=True)
    info = json.loads(run(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(movie)]))
    if not any(s['codec_type']=='video' for s in info['streams']):
        raise ValueError('没有视频轨道')
    duration = float(info['format']['duration'])
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('无有效时长')
    out = (a.output or Path('results')/(movie.stem+'_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))).resolve()
    out.mkdir(parents=True, exist_ok=False)
    print(f'采样整部影片：{timestamp(duration)}，间隔 {a.interval}s', flush=True)
    vf = f'fps=1/{a.interval},cropdetect=limit={a.black_limit}:round=2:reset=1:skip=0,metadata=mode=print:file=-'
    # No shell, no filename inside filter expressions: Unicode and spaces are safe.
    cmd = ['ffmpeg','-nostdin','-hide_banner','-v','error','-i',str(movie),'-map','0:v:0','-vf',vf,'-an','-sn','-dn','-f','null','-']
    with (out/'metadata.txt').open('w') as stdout, (out/'ffmpeg.log').open('w') as stderr:
        result = subprocess.run(cmd,stdout=stdout,stderr=stderr)
    if result.returncode:
        raise RuntimeError(f'FFmpeg 失败，见 {out / "ffmpeg.log"}')
    samples = [s for s in parse_metadata((out/'metadata.txt').read_text()) if 0 <= s['time'] < duration]
    body, support, ads = detect(samples,duration,a.interval,a.tolerance,a.height_ratio,a.min_duration,a.merge_gap)
    report = {'source': str(movie), 'duration': duration,'main_crop': body,'main_support': support,
              'parameters': {k:str(v) if isinstance(v,Path) else v for k,v in vars(a).items()},
              'boundary_uncertainty_seconds': a.interval, 'candidates': ads,
              'warnings': ['置信度仅指画幅异常证据，不代表确定为广告；边界须人工复核。']}
    if support < .6:
        report['warnings'].append('主体画幅占比低于 60%，多画幅影片的检测可能不可靠。')
    preview = out/'previews'
    if not a.no_previews:
        preview.mkdir()
        for i, ad in enumerate(ads,1):
            ad['previews'] = []
            for label,t in [('start',ad['start']+a.interval),('middle',(ad['start']+ad['end'])/2),('end',ad['end']-a.interval)]:
                name = f'ad_{i:03}_{label}.jpg'
                run(['ffmpeg','-nostdin','-v','error','-ss',str(max(ad['start'],min(t,ad['end']-.01))),'-i',str(movie),'-map','0:v:0','-frames:v','1','-vf','scale=640:-2','-q:v','3',str(preview/name)])
                if not (preview/name).is_file():
                    raise RuntimeError(f'截图未生成：{name}')
                ad['previews'].append('previews/'+name)
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    (out/'samples.json').write_text(json.dumps(samples,ensure_ascii=False))
    lines = [f'主体有效画幅：{croptext(body)}（占比 {support:.1%}）','', '疑似广告：']
    sections = []
    for i,ad in enumerate(ads,1):
        desc = f'{timestamp(ad["start"])} - {timestamp(ad["end"])} | 持续 {ad["duration"]:.1f} 秒 | {croptext(ad["crop"])} | 置信度：{ad["confidence"]}'
        lines.append(desc)
        sections.append(f'<section><h2>候选 {i}</h2><p>{html.escape(desc)}</p>'+''.join(f'<a href="{src}"><img src="{src}"></a>' for src in ad.get('previews',[]))+'</section>')
    if not ads:
        lines.append('未发现符合阈值的候选（不等于影片无广告）。')
    lines += ['',*report['warnings']]
    (out/'report.txt').write_text('\n'.join(lines))
    (out/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>画幅异常预览</title><style>body{font:16px system-ui;margin:40px;background:#16191e;color:#eee}img{width:31%;margin:1%}section{padding:15px;background:#242932;margin:20px 0}p{line-height:1.7}</style><h1>'+html.escape(movie.name)+'</h1><p>'+html.escape(lines[0])+'</p><p>'+html.escape(' '.join(report['warnings']))+'</p>'+''.join(sections))
    print('\n'.join(lines))
    print(f'\n报告与预览：{out / "index.html"}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as e:
        print(f'错误：{e}',file=sys.stderr)
        sys.exit(1)
