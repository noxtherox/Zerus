import http.server,json,pathlib,hashlib,base64,re,subprocess,tempfile,argparse
parser=argparse.ArgumentParser(description="Local synthetic native attachment transport fixture; never use personal inputs.")
parser.add_argument("--port",type=int,default=8769);parser.add_argument("--log",type=pathlib.Path,required=True);parser.add_argument("--proof",type=pathlib.Path,required=True);args=parser.parse_args()
LOG=args.log
LOG.parent.mkdir(parents=True,exist_ok=True);args.proof.parent.mkdir(parents=True,exist_ok=True)
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  data=json.dumps({'zerusNativeAgentFixture':True,'data':[{'id':'zerus-native-attachment-fixture'}]}).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data)
 def do_POST(self):
  request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  # Local synthetic fixtures only. Retain actual bodies without credentials.
  with LOG.open('a') as f:f.write(json.dumps(request)+'\n')
  images=[];text=[]
  for message in request['messages']:
   content=message.get('content','')
   if isinstance(content,str):text.append(content)
   else:
    for part in content:
     if part.get('type')=='text':text.append(part.get('text',''))
     elif part.get('type')=='image_url':
      url=part['image_url']['url'];assert url.startswith('data:image/jpeg;base64,')
      pixels=base64.b64decode(url.split(',',1)[1],validate=True);assert pixels[:2]==b'\xff\xd8'
      with tempfile.NamedTemporaryFile(suffix='.jpg') as f:
       f.write(pixels);f.flush();info=subprocess.check_output(['sips','-g','pixelWidth','-g','pixelHeight',f.name],text=True)
      dimensions=[int(v) for v in re.findall(r'pixel(?:Width|Height): (\d+)',info)]
      assert len(dimensions)==2 and max(dimensions)<=1024 and min(dimensions)>0
      images.append({'sha256':hashlib.sha256(pixels).hexdigest(),'bytes':len(pixels),'dimensions':dimensions})
  prompt='\n'.join(text);assert images,'No actual image pixels reached the provider'
  marker='Cobalt attachment owner'
  assert marker in prompt,'No document text reached the provider'
  with args.proof.open('a') as f:f.write(json.dumps({'images':images,'documentMarker':marker,'model':request['model'],'mode':re.search(r'Mode: (Ask|Review|Edit)',prompt).group(1)})+'\n')
  delta={'content':'Synthetic attachment transport verified: actual JPEG pixels and Cobalt document text received.'}
  self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
  for c in [{'choices':[{'delta':delta,'finish_reason':None}]},{'choices':[{'delta':{},'finish_reason':'stop'}],'usage':{'prompt_tokens':100,'completion_tokens':30}}]:
   self.wfile.write(('data: '+json.dumps(c)+'\n\n').encode());self.wfile.flush()
  self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
http.server.ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
