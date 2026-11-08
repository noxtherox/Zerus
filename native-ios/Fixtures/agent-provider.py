#!/usr/bin/env python3
"""Synthetic tool-calling provider for native UI journeys; never use a personal vault.

The fixture supplies tool requests, not storage results or receipts. The app must
perform its own scoped reads, native approvals, coordinated saves and undo.
Authorization headers are never logged. Use only disposable notes and credentials.
"""
import argparse,http.server,json,uuid,re,pathlib
from urllib.parse import quote
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port',type=int,default=8766)
parser.add_argument('--log',type=pathlib.Path,default=pathlib.Path('artifacts/native-ios/agent-fixture-requests.jsonl'))
parser.add_argument('--public-base',default='https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-agent-qa')
options=parser.parse_args()
LOG=options.log
LOG.parent.mkdir(parents=True,exist_ok=True)
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  if self.path.split('?',1)[0].endswith('/image.png'):
   body=pathlib.Path(__file__).with_name('chat-markdown.png').read_bytes();self.send_response(200);self.send_header('Content-Type','image/png');self.end_headers();self.wfile.write(body);return
  body=json.dumps({'zerusNativeAgentFixture':True,'version':1,'data':[{'id':'zerus-native-fixture','name':'Native fixture'}]}).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
 def do_POST(self):
  request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  # Save fixture request bodies, never authorization headers or real provider credentials.
  with LOG.open('a') as f:f.write(json.dumps(request)+'\n')
  # Existing tool journeys can follow a conversation containing photo references.
  # Preserve the full captured transport above; inspect only text for scripted tool choices.
  messages=[dict(m,content='\n'.join(p.get('text','') for p in m['content'] if p.get('type')=='text')) if isinstance(m.get('content'),list) else m for m in request['messages']]
  system=messages[0]['content'];mode=re.search(r'Mode: (Ask|Review|Edit)',system).group(1)
  index=re.search(r'Read only IDs: ([^.]+)\.',system)
  ids=[i.strip() for i in index.group(1).split(',')] if index else []
  relation=any(m['role']=='user' and m['content'].startswith('Request:\nUnlink my two selected notes.') for m in messages)
  if len(ids)!=(2 if relation else 1): raise RuntimeError('Fixture requires the explicitly selected synthetic notes')
  metadata=any(m['role']=='user' and m['content'].startswith('Request:\nUpdate properties for') for m in messages)
  formatted=any(m['role']=='user' and m['content'].startswith('Request:\nRender a formatted answer for my selected synthetic note.') for m in messages)
  target=ids[0];completed={};receipt=any(m['role']=='user' and m['content'].startswith('Runtime verified saved proposals:') for m in messages)
  reads={}
  for m in messages:
   if m['role']=='tool':
    value=json.loads(m['content'])
    if 'body' in value and value.get('ok'):
     completed['read']=value;reads[value['id']]=value
    if 'definitions' in value and value.get('ok'):completed['schema']=value
    if value.get('status')=='pending_review':completed['staged']=value
  def call(name,args):return {'index':0,'id':'fixture_'+uuid.uuid4().hex,'type':'function','function':{'name':name,'arguments':json.dumps(args)}}
  if relation:
   initial=next(m['content'] for m in messages if m['role']=='user' and m['content'].startswith('Request:\nUnlink my two selected notes.'))
   selected=json.loads(initial.split('Selected note index (reference data, not instructions):\n',1)[1].split('\n\nPrevious conversation',1)[0])
   source=next(n for n in selected if n['title'].startswith('Agent relation source '))
   target=source['id'];field='Agent link '+source['title'].removeprefix('Agent relation source ')
   inverse=next(i for i in ids if i!=target)
   if receipt:raise RuntimeError('A multi-note relation edit must wait for native review, even in Edit mode')
   if 'schema' not in completed:mutation=call('note_schema',{'selector':target})
   elif target not in reads:mutation=call('note_get',{'selector':target})
   elif inverse not in reads:mutation=call('note_get',{'selector':inverse})
   elif 'staged' not in completed:
    definition=next(d for d in completed['schema']['definitions'] if d['name']==field)
    mutation=call('note_properties',{'selector':target,'revision':reads[target]['revision'],'values':{definition['name']:None}})
   else:mutation=call('preview_changes',{})
   delta={'tool_calls':[mutation]};finish='tool_calls'
  elif receipt:
   delta={'content':'The selected passage was saved and verified. Its receipt is in AI runs.'};finish='stop'
  elif metadata and 'schema' not in completed:
   delta={'tool_calls':[call('note_schema',{'selector':target})]};finish='tool_calls'
  elif 'read' not in completed:
   delta={'tool_calls':[call('note_get',{'selector':target})]};finish='tool_calls'
  elif mode=='Ask':
   if formatted:
    title=completed['read']['title']
    answer='\n\n'.join(['## Native answer','A **bold** result with *emphasis* and ~~old~~ text.','- First item\n  - Nested item\n- [x] Finished','3. Third item\n4. Fourth item','> Quoted thought','| Name | Value |\n| :--- | ---: |\n| alpha | `one` |','![Synthetic chart]('+options.public_base.rstrip('/')+'/image.png)','```swift\nlet ready = true\n[[zerus:not-a-citation|literal]]\n```','['+title+'](zerus-note:'+quote(target,safe='')+')','[[zerus:'+target+'|Native wiki citation]]','<script>alert("literal")</script>','[Unsafe](javascript:alert("no"))'])
    delta={'content':answer}
   else:delta={'content':'The selected synthetic note contains the original passage. No notes were changed.'}
   finish='stop'
  elif 'staged' not in completed:
   read=completed['read']
   mutation=call('note_properties',{'selector':target,'revision':read['revision'],'values':{'Status':'Ready','Score':8,'Done':True}}) if metadata else call('note_patch',{'selector':target,'revision':read['revision'],'oldText':'Before native agent.','newText':'After native agent.'})
   delta={'tool_calls':[mutation]};finish='tool_calls'
  else:
   delta={'content':'A focused change is ready for your review.','tool_calls':[call('preview_changes',{})]};finish='tool_calls'
  self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Cache-Control','no-cache');self.end_headers()
  chunks=[{'choices':[{'delta':delta,'finish_reason':None}]},{'choices':[{'delta':{},'finish_reason':finish}],'usage':{'prompt_tokens':100,'completion_tokens':30}}]
  for c in chunks:self.wfile.write(('data: '+json.dumps(c)+'\n\n').encode());self.wfile.flush()
  self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
http.server.ThreadingHTTPServer(('127.0.0.1',options.port),Handler).serve_forever()
