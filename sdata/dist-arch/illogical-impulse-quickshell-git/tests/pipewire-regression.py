#!/usr/bin/env python3
"""Exercise QS default/configured-node lifetime on a private, device-free server."""
import json,os,pathlib,resource,signal,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parent
binary=str(pathlib.Path(sys.argv[1]).resolve())
label=sys.argv[2]
env=os.environ.copy()
env.update(PIPEWIRE_RUNTIME_DIR=str(root/'pipewire-runtime'),PIPEWIRE_REMOTE='qs-upgrade-test',QT_QPA_PLATFORM='offscreen',QS_DISABLE_CRASH_HANDLER='1')
# All PipeWire commands carry the private socket environment.
def run(*args):
 return subprocess.check_output(args,env=env,text=True,stderr=subprocess.STDOUT,timeout=8)
def dump(): return json.loads(run('pw-dump'))
def create(name,kind):
 run('pw-cli','create-node','adapter',f'{{ factory.name = support.null-audio-sink node.name = {name} media.class = Audio/{kind} audio.position = [ FL FR ] object.linger = true }}')
 for _ in range(30):
  for obj in dump():
   if obj.get('info',{}).get('props',{}).get('node.name')==name:return obj['id']
  time.sleep(.05)
 raise RuntimeError('missing node '+name)
def metadata(key,name):
 run('pw-metadata','-n','default','0',key,json.dumps({'name':name}),'Spa:String:JSON')
 time.sleep(.07)
def status():
 return json.loads(run(binary,'-p',str(root/'probe'),'ipc','call','probe','status'))
def limitcore():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
# Clear leftovers only in the isolated server.
for obj in dump():
 if obj.get('type')=='PipeWire:Interface:Node':run('pw-cli','destroy',str(obj['id']))
log=(root/(label+'-pipewire.log')).open('w')
launch=[binary,'-p',str(root/'probe'),'--no-color']
if os.environ.get('QS_TEST_GDB') == '1':
 launch=['gdb','-batch','-ex','set debuginfod enabled off','-ex','run','-ex','thread apply all bt 12','--args']+launch
p=subprocess.Popen(launch,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=limitcore)
result={'binary':binary,'pid':p.pid,'cycles':0,'transitions':0}
try:
 for _ in range(80):
  try:
   state=status();break
  except Exception:
   if p.poll() is not None:raise RuntimeError('probe exited during startup')
   time.sleep(.1)
 else:raise RuntimeError('IPC did not become ready')
 for cycle in range(20):
  for kind in ['source','sink']:
   a=f'probe-{kind}-A-{cycle}';b=f'probe-{kind}-B-{cycle}'
   aid=create(a,kind.capitalize());bid=create(b,kind.capitalize())
   metadata('default.audio.'+kind,a)
   metadata('default.configured.audio.'+kind,a)
   state=status()
   field='preferred'+kind.capitalize()
   assert state[kind]==a and state[field]==a,state
   # Both references share A. Move the preferred role, then delete A while
   # current-default still refers to it: the old blanket disconnect loses
   # the current-default destruction handler.
   metadata('default.configured.audio.'+kind,b)
   run('pw-cli','destroy',str(aid));time.sleep(.12)
   metadata('default.audio.'+kind,b)
   state=status()
   assert state[kind]==b and state[field]==b,state
   run('pw-cli','destroy',str(bid));time.sleep(.12)
   state=status()
   assert state[kind] is None and state[field] is None,state
   result['transitions']+=6
  result['cycles']+=1
  print(label,'cycle',cycle+1,'passed',flush=True)
 result['passed']=True
except Exception as e:
 result['passed']=False;result['error']=str(e);result['exitCode']=p.poll()
finally:
 try:os.killpg(p.pid,signal.SIGTERM)
 except ProcessLookupError:pass
 try:p.wait(timeout=5)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
 log.close()
 (root/(label+'-pipewire-result.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result),flush=True)
sys.exit(0 if result.get('passed') else 1)
