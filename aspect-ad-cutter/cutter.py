"""Keyframe-aligned, stream-copy export. Never overwrites the source."""
import csv
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile


def run(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode:
        raise RuntimeError(p.stderr[-5000:])
    return p.stdout


def probe(path):
    return json.loads(run(['ffprobe','-v','error','-show_format','-show_streams','-show_chapters','-of','json',str(path)]))


def fingerprint(path):
    s = Path(path).stat()
    return [s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns]


def merge_ranges(ranges):
    out = []
    for start,end in sorted(ranges):
        if out and start <= out[-1][1]+1e-6:
            out[-1][1] = max(end,out[-1][1])
        else:
            out.append([start,end])
    return out


def make_plan(source, ranges):
    source = Path(source).resolve(strict=True)
    info = probe(source)
    duration = float(info['format']['duration'])
    origin = float(info['format'].get('start_time',0))
    if not ranges or not math.isfinite(duration) or duration <= 0:
        raise ValueError('请至少选择一个有效广告区间')
    for start,end in ranges:
        if not all(math.isfinite(x) for x in (start,end)) or not 0 <= start < end <= duration:
            raise ValueError('区间必须满足 0 ≤ 开始 < 结束 ≤ 影片时长')
    videos = [s for s in info['streams'] if s['codec_type']=='video' and not s.get('disposition',{}).get('attached_pic')]
    if len(videos)!=1:
        raise ValueError('目前无损导出支持单路视频；多视频轨需要独立关键帧对齐')
    # Packet timestamps survive in-stream resolution changes without frame-number assumptions.
    raw = json.loads(run(['ffprobe','-v','error','-select_streams',str(videos[0]['index']),'-show_packets','-show_entries','packet=pts_time,flags','-of','json',str(source)]))
    keys = sorted(set([0.0,duration]+[max(0,min(duration,float(p['pts_time'])-origin)) for p in raw['packets'] if 'K' in p.get('flags','') and 'pts_time' in p]))
    requested = merge_ranges(ranges)
    aligned = merge_ranges([[max(k for k in keys if k<=start), min(k for k in keys if k>=end)] for start,end in requested])
    if sum(b-a for a,b in aligned) >= duration-.01:
        raise ValueError('对齐后的区间会删除整部影片，无法导出')
    points = sorted(set([0.0,duration]+[t for r in aligned for t in r]))
    pieces = [{'start':a,'end':b,'keep':not any(a>=x-1e-6 and b<=y+1e-6 for x,y in aligned)} for a,b in zip(points,points[1:])]
    return {'source':str(source),'fingerprint':fingerprint(source),'duration':duration,'requested':requested,'removed':aligned,'pieces':pieces,
            'expected_duration':sum(p['end']-p['start'] for p in pieces if p['keep']),
            'extra_removed':sum(b-a for a,b in aligned)-sum(b-a for a,b in requested),
            'streams':[{'type':s['codec_type'],'codec':s['codec_name']} for s in info['streams']],
            'chapter_count':len(info.get('chapters',[])),
            'video_start':float(videos[0].get('start_time',origin))-origin}


def remap_chapters(chapters, pieces):
    result = []
    for chapter in chapters:
        a,b = float(chapter['start_time']),float(chapter['end_time'])
        offset = 0
        chunks = []
        for piece in pieces:
            if not piece['keep']:
                continue
            start,end = max(a,piece['start']),min(b,piece['end'])
            if end>start:
                chunks.append((offset+start-piece['start'],offset+end-piece['start']))
            offset += piece['end']-piece['start']
        if chunks:
            result.append({'start':chunks[0][0],'end':chunks[-1][1],'tags':chapter.get('tags',{})})
    return result


def escape_metadata(s):
    return str(s).replace('\\','\\\\').replace('\n','\\\n').replace('=','\\=').replace(';','\\;').replace('#','\\#')


def export(plan, destination, progress=lambda msg: None):
    source = Path(plan['source'])
    dest = Path(destination).expanduser().resolve()
    if fingerprint(source)!=plan['fingerprint']:
        raise ValueError('源文件已改变，请重新检测并确认')
    if dest == source.resolve() or dest.exists():
        raise ValueError('输出文件已存在或与源文件相同，请换一个文件名')
    if dest.suffix.lower()!='.mkv':
        raise ValueError('无损导出目前使用 MKV，以尽量保留音轨和字幕')
    dest.parent.mkdir(parents=True,exist_ok=True)
    info = probe(source)
    with tempfile.TemporaryDirectory(prefix='.aspect-cut-',dir=dest.parent) as td:
        work = Path(td)
        # segment_times is relative to the reference video's first PTS, while
        # the UI uses the container clock. MKV also quantizes to milliseconds.
        points = sorted(set(p['end'] for p in plan['pieces'][:-1]))
        progress('正在按已确认的关键帧拆分视频（无重编码）…')
        run(['ffmpeg','-nostdin','-v','error','-copyts','-start_at_zero','-i',str(source),'-map','0','-map_chapters','-1','-c','copy','-avoid_negative_ts','disabled',
             '-f','segment','-segment_format_options','avoid_negative_ts=disabled','-segment_times',','.join(f'{max(0,t-plan["video_start"]):.9f}' for t in points),'-segment_time_delta','0.001',
             '-reset_timestamps','1','-segment_list',str(work/'segments.csv'),'-segment_list_type','csv',str(work/'part_%03d.mkv')])
        rows = list(csv.reader((work/'segments.csv').read_text().splitlines()))
        if len(rows)!=len(plan['pieces']):
            raise RuntimeError('实际分段数量与确认计划不一致，已停止导出')
        kept=[]
        actual_pieces=[]
        # Segment list reports the muxer's actual boundaries, including timestamp offsets.
        base = float(rows[0][1])
        for row,piece in zip(rows,plan['pieces']):
            start,end=float(row[1])-base,float(row[2])-base
            if abs(start-piece['start'])>.25 or abs(end-piece['end'])>.5:
                raise RuntimeError('实际关键帧切点偏离确认计划超过容差，已停止导出')
            actual_pieces.append(dict(piece,start=start,end=end))
            if piece['keep']:
                kept.append(work/Path(row[0]).name)
        signatures=[]
        for path in kept:
            streams=probe(path)['streams']
            signatures.append([(s['codec_type'],s['codec_name'],s.get('width'),s.get('height'),s.get('sample_rate'),s.get('channels')) for s in streams])
        if any(sig!=signatures[0] for sig in signatures[1:]):
            raise RuntimeError('保留片段的轨道或分辨率不一致，无法安全无损拼接')
        # Controlled temporary basenames: no quoting of user-supplied paths in concat syntax.
        (work/'concat.txt').write_text(''.join(f"file '{path.name}'\n" for path in kept))
        chapters=remap_chapters(info.get('chapters',[]),actual_pieces)
        metadata=';FFMETADATA1\n'
        for ch in chapters:
            metadata+=f'[CHAPTER]\nTIMEBASE=1/1000\nSTART={round(ch["start"]*1000)}\nEND={round(ch["end"]*1000)}\n'
            metadata+=''.join(f'{escape_metadata(k)}={escape_metadata(v)}\n' for k,v in ch['tags'].items())
        (work/'chapters.txt').write_text(metadata)
        progress('正在拼接正片，保留音轨、字幕与元数据…')
        run(['ffmpeg','-nostdin','-v','error','-f','concat','-safe','0','-i',str(work/'concat.txt'),'-i',str(source),'-f','ffmetadata','-i',str(work/'chapters.txt'),
             '-map','0','-map_metadata','1','-map_chapters','2','-c','copy',str(work/'clean.mkv')])
        output_info=probe(work/'clean.mkv')
        if len(output_info['streams'])!=len(info['streams']):
            raise RuntimeError('输出轨道数量不一致，已停止导出')
        if abs(float(output_info['format']['duration'])-plan['expected_duration'])>max(1,len(kept)*.15):
            raise RuntimeError('输出时长与计划不符，已停止导出')
        progress('正在验证导出视频可完整解码…')
        run(['ffmpeg','-nostdin','-v','error','-xerror','-i',str(work/'clean.mkv'),'-map','0:v:0','-map','0:a?','-f','null','-'])
        # Atomic no-clobber publish; source is never opened for writing.
        if fingerprint(source)!=plan['fingerprint']:
            raise ValueError('导出期间源文件发生变化，已停止发布结果')
        os.link(work/'clean.mkv',dest)
    return {'output':str(dest),'duration':float(output_info['format']['duration']),'streams':len(output_info['streams'])}
