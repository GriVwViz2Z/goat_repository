#!/usr/bin/env python3
"""Local browser GUI, no third-party Python packages."""
import argparse
import json
import os
from pathlib import Path
import secrets
import re
import subprocess
import sys
import threading
import tempfile
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
from cutter import make_plan,export,fingerprint,probe

ROOT=Path(__file__).resolve().parent
TOKEN=secrets.token_urlsafe(32)
LOCK=threading.Lock()
STATE={'busy':False,'status':'选择影片，或载入已有检测报告。','report':None,'plan':None,'error':None,'result':None}
REPORT_DIR=None

def update(**kwargs):
    with LOCK:
        STATE.update(kwargs)

def job(action):
    with LOCK:
        if STATE['busy']:
            raise ValueError('当前任务尚未完成')
        STATE.update(busy=True,error=None,result=None)
    def worker():
        try:
            action()
        except Exception as e:
            update(error=str(e),status='操作未完成')
        finally:
            update(busy=False)
    threading.Thread(target=worker,daemon=True).start()

def load_report(path):
    global REPORT_DIR
    path=Path(path).expanduser().resolve(strict=True)
    report=json.loads(path.read_text())
    source=Path(report['source']).resolve(strict=True)
    report['source']=str(source)
    report['fingerprint']=fingerprint(source)
    if not isinstance(report['candidates'],list):
        raise ValueError('无效报告')
    REPORT_DIR=path.parent
    update(report=report,plan=None,status='检测完成。查看截图、播放核实并勾选要删除的区间。')

def detect(source):
    source=Path(source).expanduser().resolve(strict=True)
    out=ROOT/'results'/('gui_'+time.strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3))
    update(status='正在扫描整部电影并生成截图…',plan=None,report=None)
    duration=float(probe(source)['format']['duration'])
    with tempfile.TemporaryFile(mode='w+') as log:
        p=subprocess.Popen([sys.executable,str(ROOT/'ad_detect.py'),str(source),'--output',str(out)],stdout=log,stderr=log)
        while p.poll() is None:
            metadata=out/'metadata.txt'
            if metadata.exists():
                with metadata.open('rb') as f:
                    f.seek(max(0,metadata.stat().st_size-4096))
                    times=re.findall(rb'pts_time:([0-9.]+)',f.read())
                if times:
                    percent=min(99,float(times[-1])/duration*100)
                    update(status=f'正在检测 / 生成截图… {percent:.0f}%')
            time.sleep(.5)
        if p.returncode:
            log.seek(0)
            raise RuntimeError(log.read()[-4000:])
    load_report(out/'report.json')

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):
        pass
    def reply(self,obj,status=200):
        data=json.dumps(obj,ensure_ascii=False).encode()
        self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(data)
    def auth(self):
        return self.headers.get('X-App-Token')==TOKEN
    def do_GET(self):
        parsed=urlparse(self.path)
        if parsed.path=='/':
            if parse_qs(parsed.query).get('token',[''])[0]!=TOKEN:
                return self.reply({'error':'请使用启动器打开界面'},403)
            data=(ROOT/'gui.html').read_text().replace('__TOKEN__',TOKEN).encode()
            self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Referrer-Policy','no-referrer'); self.end_headers(); self.wfile.write(data)
        elif parsed.path=='/state' and self.auth():
            with LOCK:
                self.reply(STATE)
        elif parsed.path=='/preview' and parse_qs(parsed.query).get('token',[''])[0]==TOKEN:
            try:
                path=(REPORT_DIR/parse_qs(parsed.query)['path'][0]).resolve()
                if REPORT_DIR not in path.parents or path.suffix.lower()!='.jpg':
                    raise ValueError('无效截图路径')
                data=path.read_bytes()
                self.send_response(200);self.send_header('Content-Type','image/jpeg');self.end_headers();self.wfile.write(data)
            except Exception:
                self.reply({'error':'截图不可用'},404)
        else:
            self.reply({'error':'not found'},404)
    def do_POST(self):
        if not self.auth():
            return self.reply({'error':'未授权的请求'},403)
        try:
            data=json.loads(self.rfile.read(min(int(self.headers.get('Content-Length',0)),65536)))
            action=urlparse(self.path).path
            if action=='/pick':
                script='POSIX path of (choose file with prompt "选择电影或 report.json")'
                p=subprocess.run(['osascript','-e',script],capture_output=True,text=True)
                return self.reply({'path':p.stdout.strip() if p.returncode==0 else ''})
            if action=='/detect':
                job(lambda:detect(data['source']))
            elif action=='/load':
                job(lambda:load_report(data['path']))
            elif action=='/plan':
                def prepare():
                    update(status='正在查找关键帧，计算实际删除范围…',plan=None)
                    report=STATE['report']
                    if not report or fingerprint(report['source'])!=report['fingerprint']:
                        raise ValueError('源文件状态已改变，请重新检测')
                    plan=make_plan(report['source'],[[float(r[0]),float(r[1])] for r in data['ranges']])
                    plan['id']=secrets.token_hex(16)
                    update(plan=plan,status='请核对下方实际删除范围，再确认导出。')
                job(prepare)
            elif action=='/export':
                plan=STATE['plan']
                if not plan or data.get('plan_id')!=plan['id'] or data.get('confirmed') is not True:
                    raise ValueError('请先生成并确认删除计划')
                def save():
                    result=export(plan,data['destination'],lambda msg:update(status=msg))
                    update(result=result,status='导出完成，原文件已保留。',plan=None)
                job(save)
            elif action=='/play':
                report=STATE['report']
                if not report:
                    raise ValueError('请先检测')
                t=max(0,float(data['time']))
                subprocess.Popen(['ffplay','-v','error','-ss',str(t),'-t','20','-autoexit','-window_title','广告区间核实','-i',report['source']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            elif action=='/reveal':
                if STATE['result']:
                    subprocess.Popen(['open','-R',STATE['result']['output']])
            else:
                raise ValueError('未知操作')
            self.reply({'ok':True})
        except Exception as e:
            self.reply({'error':str(e)},400)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-browser',action='store_true')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    os.environ['PATH']='/opt/homebrew/bin:/usr/local/bin:'+os.environ.get('PATH','')
    if args.report:
        load_report(args.report)
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    url=f'http://127.0.0.1:{server.server_port}/?token={TOKEN}'
    print(url,flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
