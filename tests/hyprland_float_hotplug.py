#!/usr/bin/env python3
"""Isolated real-compositor regression for floating windows on monitor reconnect.

Run: dbus-run-session -- python3 tests/hyprland_float_hotplug.py
Requires KWin Wayland, Hyprland with Lua config, and Kitty. Creates a virtual
parent and a private nested compositor; never dispatches into the live desktop.
Use --baseline to demonstrate the original drift on an affected compositor.
"""
import argparse
import os,json,subprocess,tempfile,time
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
from pathlib import Path
out=Path(tempfile.mkdtemp(prefix='float-hotplug-'));rt=Path(tempfile.mkdtemp(prefix='fh-'));rt.chmod(0o700)
env=os.environ.copy()
for key in ['WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE']:env.pop(key,None)
env.update(XDG_RUNTIME_DIR=str(rt),XDG_CONFIG_HOME=str(out/'config'),XDG_CACHE_HOME=str(out/'cache'),XDG_DATA_HOME=str(out/'data'),XDG_STATE_HOME=str(out/'state'),QT_QPA_PLATFORM='offscreen',AQ_DRM_DEVICES='/nonexistent-test-device',QT_NO_XDG_DESKTOP_PORTAL='1',NO_AT_BRIDGE='1',XDG_CURRENT_DESKTOP='')
procs=[];logs=[]
def launch(args,name):
 log=(out/(name+'.log')).open('w');logs.append(log);p=subprocess.Popen(args,env=env,stdout=log,stderr=subprocess.STDOUT);procs.append(p);return p
def until(fn):
 end=time.monotonic()+20
 while time.monotonic()<end:
  try:
   v=fn()
   if v:return v
  except (subprocess.SubprocessError,json.JSONDecodeError):pass
  time.sleep(.08)
 raise RuntimeError('Timeout; '+str(out))
def ctl(*args):return subprocess.check_output(['hyprctl',*args],env=env,text=True,timeout=5).strip()
def clients():return json.loads(ctl('clients','-j'))
def save(label):
 data={k:json.loads(ctl(k,'-j')) for k in ['clients','monitors','workspaces']};(out/(label+'.json')).write_text(json.dumps(data,indent=2))
 print(label,[(c['class'],c['workspace']['id'],c['at'],c['size']) for c in data['clients']],flush=True)
 return data
try:
 launch(['kwin_wayland','--virtual','--width','1920','--height','1080','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--socket','test-parent'],'kwin')
 until(lambda:(rt/'test-parent').exists());env.update(WAYLAND_DISPLAY='test-parent',QT_QPA_PLATFORM='wayland')
 config=out/'hyprland.lua';config.write_text('hl.monitor({output="",mode="1920x1080@60",position="auto",scale=1})\nhl.config({animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true},input={follow_mouse=0}})\n')
 launch(['Hyprland','--config',str(config)],'hyprland')
 sock=until(lambda:next((rt/'hypr').glob('*/.socket.sock'),None));env['HYPRLAND_INSTANCE_SIGNATURE']=sock.parent.name
 env['WAYLAND_DISPLAY']=until(lambda:next((p.name for p in rt.glob('wayland-*') if not p.name.endswith('.lock')),None))
 until(lambda:json.loads(ctl('monitors','-j')))
 print('output create',ctl('output','create','headless','BOUNDS-ARZOPA'),flush=True)
 until(lambda:len(json.loads(ctl('monitors','-j')))==2)
 print(ctl('eval','hl.monitor({output="BOUNDS-ARZOPA",mode="1920x1080@60",position="1920x500",scale=1}); hl.workspace_rule({workspace="6",monitor="BOUNDS-ARZOPA"}); hl.dispatch(hl.dsp.focus({workspace="6"}))'),flush=True)
 launch(['kitty','--config','NONE','--class','float-bounds-probe','/usr/bin/sleep','600'],'kitty')
 client=until(lambda:next((c for c in clients() if c['class']=='float-bounds-probe'),None));addr=client['address']
 print(ctl('eval',f'local w=hl.get_window("address:{addr}"); hl.dispatch(hl.dsp.window.float({{window=w,action="enable"}})); hl.dispatch(hl.dsp.window.resize({{window=w,x=700,y=450,relative=false}})); hl.dispatch(hl.dsp.window.move({{window=w,x=2080,y=620,relative=false}})); hl.dispatch(hl.dsp.focus({{workspace="7"}}))'),flush=True)
 save('before')
 guard=Path(__file__).resolve().parents[1]/'dots/.config/hypr/custom/float-hotplug.lua'
 if not args.baseline: print('guard',ctl('eval','dofile('+json.dumps(str(guard))+')'),flush=True)
 for i in range(3):
  print('remove',ctl('output','remove','BOUNDS-ARZOPA'),flush=True);time.sleep(.3);save(f'removed-{i}')
  print('create',ctl('output','create','headless','BOUNDS-ARZOPA'),flush=True);time.sleep(.5);data=save(f'returned-{i}'); c=next(c for c in data['clients'] if c['address']==addr); assert (c['at']!=[2080,620] if args.baseline else c['at']==[2080,620]),c['at']; assert c['size']==[700,450]
 assert not ctl('configerrors'); print('PASS:', 'native drift reproduced' if args.baseline else 'three hotplug cycles retained exact position and size', 'OUT',out,flush=True)
finally:
 for p in reversed(procs):
  if p.poll() is None:
   p.terminate()
   try:p.wait(timeout=5)
   except subprocess.TimeoutExpired:p.kill();p.wait()
 for l in logs:l.close()
