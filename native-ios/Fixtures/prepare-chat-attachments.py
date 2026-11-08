#!/usr/bin/env python3
"""Prepare synthetic Files/Photos inputs in the dedicated QA simulator only."""
import argparse,hashlib,json,pathlib,struct,subprocess,tempfile,zlib
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator',required=True)
parser.add_argument('--proof',type=pathlib.Path,required=True)
args=parser.parse_args()
def run(*command): return subprocess.check_output(command,text=True).strip()
devices=json.loads(run('xcrun','simctl','list','devices','--json'))['devices']
device=next((d for group in devices.values() for d in group if d['udid']==args.simulator),None)
if not device or device['name']!='Zerus Native Move QA': raise SystemExit('Use the dedicated Zerus Native Move QA simulator, never a personal device.')
container=pathlib.Path(run('xcrun','simctl','get_app_container',args.simulator,'com.zerus.notes.native','data'))
text='Cobalt attachment owner café 🌿 漢字. Original source stays unchanged.'.encode('utf-16')
file=container/'Documents'/'Zerus attachment owner.txt';file.write_bytes(text)
w,h=1200,800
raw=b''.join(b'\x00'+b'\xe9\x42\x35'*(w//2)+b'\x24\x64\xe8'*(w//2) for _ in range(h))
def chunk(kind,b): return struct.pack('>I',len(b))+kind+b+struct.pack('>I',zlib.crc32(kind+b)&0xffffffff)
photo=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
image=pathlib.Path(tempfile.gettempdir())/'Zerus attachment photo owner.png';image.write_bytes(photo)
run('xcrun','simctl','addmedia',args.simulator,str(image))
args.proof.parent.mkdir(parents=True,exist_ok=True)
args.proof.write_text(json.dumps({'simulator':args.simulator,'filesRelativePath':'Documents/'+file.name,'filesSHA256':hashlib.sha256(text).hexdigest(),'photoPath':str(image),'photoSHA256':hashlib.sha256(photo).hexdigest(),'photoWidth':w,'photoHeight':h},indent=2)+'\n')
print('Synthetic Files and Photos fixtures prepared; originals recorded in',args.proof)
