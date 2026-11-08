#!/usr/bin/env python3
"""One-shot native QA install/container-relocation fixture. Never targets a physical device.

It preserves application data as actual files/inodes, installs through simctl,
then returns a receipt. It never rewrites bookmarks, chat records or draft values.
"""
import argparse,hashlib,http.server,json,pathlib,shutil,subprocess,threading,uuid
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
parser.add_argument('--port',type=int,default=8771)
args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
DEVICE='9A0184A7-2BD1-43B6-9CBB-532270F9DD5C';BUNDLE='com.zerus.notes.native'
lock=threading.Lock();state={'zerusNativeContainerFixture':True,'status':'ready'}
def run(*command,check=True):
 p=subprocess.run(command,capture_output=True,text=True,timeout=30)
 if check and p.returncode:raise RuntimeError(p.stderr or p.stdout)
 return p

def container():return pathlib.Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data').stdout.strip())
def inventory(root):
 return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for name in ['Documents','Library/Application Support','Library/Preferences'] for p in (root/name).rglob('*') if p.is_file() and not p.is_symlink()}
def install():
 devices=json.loads(run('xcrun','simctl','list','devices','--json').stdout)['devices']
 assert any(d['udid']==DEVICE and d['name']=='Zerus Native Move QA' for rows in devices.values() for d in rows)
 assert run('/usr/libexec/PlistBuddy','-c','Print :CFBundleIdentifier',str(args.app/'Info.plist')).stdout.strip()==BUNDLE
 old=container();before=inventory(old)
 state['status']='installing';run('xcrun','simctl','install',DEVICE,str(args.app));new=container();kind='normal-install'
 if old==new:
  # A normal update need not relocate data. Exercise a real new OS-registered
  # container while retaining the exact files/inodes, without fabricating app state.
  state['status']='relocating-preserved-data';kind='install-and-preserved-data-relocation'
  backup=args.output/('preserved-data-'+uuid.uuid4().hex);shutil.move(str(old),str(backup))
  try:
   removed=run('xcrun','simctl','uninstall',DEVICE,BUNDLE,check=False)
   run('xcrun','simctl','install',DEVICE,str(args.app));new=container();assert new!=old
   fresh=args.output/('fresh-container-'+uuid.uuid4().hex);fresh.mkdir()
   for source in list(backup.iterdir()):
    if source.name=='.com.apple.mobile_container_manager.metadata.plist':continue
    target=new/source.name
    if target.exists() or target.is_symlink():shutil.move(str(target),str(fresh/source.name))
    shutil.move(str(source),str(target))
  except Exception:
   state['preservedData']=str(backup);raise
 after=inventory(new);assert before==after,'App data changed during host handoff'
 receipt={'zerusNativeContainerFixture':True,'status':'complete','kind':kind,'containerBefore':str(old),'containerAfter':str(new),'containerChanged':old!=new,'preservedFileCount':len(before),'privateAndDocumentBytesPreservedBeforeAppLaunch':True,'metadataOrBookmarkRewriting':False,'installedApp':str(args.app)}
 (args.output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 (args.output/'before-files.json').write_text(json.dumps(before,indent=2)+'\n');(args.output/'after-files.json').write_text(json.dumps(after,indent=2)+'\n')
 return receipt
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,code,value):
  body=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
 def do_GET(self):self.reply(200,state)
 def do_POST(self):
  if self.path!='/install':return self.reply(404,{'error':'unknown fixture action'})
  with lock:
   if state['status']!='ready':return self.reply(409,state)
   try:state.update(install());self.reply(200,state)
   except Exception as error:
    state.update(status='failed',error=str(error));(args.output/'failure.json').write_text(json.dumps(state,indent=2)+'\n');self.reply(500,state)
http.server.ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
