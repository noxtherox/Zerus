#!/usr/bin/env python3
"""Disposable image source for native HTML-paste UI verification.

No notes or credentials are accepted. Logs record the route, public User-Agent,
and whether an unexpected Cookie/Authorization header was present, never its contents.
"""
import argparse,base64,html,http.server,json,pathlib,struct,time,zlib
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port',type=int,default=8767)
parser.add_argument('--log',type=pathlib.Path,default=pathlib.Path('artifacts/native-ios/html-clipboard-fixture-requests.jsonl'))
parser.add_argument('--public-base',default='https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-clipboard-qa')
options=parser.parse_args();options.log.parent.mkdir(parents=True,exist_ok=True)
def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
width,height=128,64
rows=b''.join(b'\0'+bytes([143,77,176])*width for _ in range(height))
PNG=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  path=self.path.split('?',1)[0]
  with options.log.open('a') as f:f.write(json.dumps({'path':path,'authorizationPresent':bool(self.headers.get('Authorization')),'cookiePresent':bool(self.headers.get('Cookie')),'userAgent':self.headers.get('User-Agent','')[:180]})+'\n')
  if path=='/health':
   body=json.dumps({'zerusNativeClipboardFixture':True,'imageBase64':base64.b64encode(PNG).decode()}).encode();kind='application/json'
  elif path=='/sample':
   image=html.escape(options.public_base.rstrip('/')+'/image.png',quote=True)
   body=('''<!doctype html><html lang="en"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Native clipboard check</title>
   <style>body{font:17px -apple-system;padding:20px;line-height:1.5}main{padding:16px;border:1px solid #888;border-radius:12px}img{width:128px;height:64px}</style>
   <p>Tap inside the box, select all, then copy.</p><main contenteditable="true" spellcheck="false" autocorrect="off" autocapitalize="off">
   <h2>Native Safari clipboard</h2><p>A <strong>bold</strong> test with <em>italic</em> text and <a href="https://example.com/native-clipboard">a link</a>.</p>
   <ul><li>First list item</li><li>Second list item</li></ul><p><img src="'''+image+'''" alt="Synthetic purple chart"></p></main></html>''').encode();kind='text/html; charset=utf-8'
  elif path=='/redirect.png':
   self.send_response(302);self.send_header('Location','image.png');self.end_headers();return
  elif path=='/large.png':
   try:
    self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Content-Length',str(51*1024*1024));self.end_headers()
    self.wfile.write(b'\0'*16384);self.wfile.flush();time.sleep(30)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  elif path in ['/image.png','/slow.png']:
   if path=='/slow.png':time.sleep(8)
   body=PNG;kind='image/png'
  else:self.send_error(404);return
  try:
   self.send_response(200);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
  except (BrokenPipeError,ConnectionResetError):pass
http.server.ThreadingHTTPServer(('127.0.0.1',options.port),Handler).serve_forever()
