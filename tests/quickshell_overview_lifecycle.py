#!/usr/bin/env python3
"""Bounded, private native-Wayland reproduction of real overview captures."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

BASE = Path(tempfile.mkdtemp(prefix='qs-overview-lifecycle-'))
OUT = BASE
RUN = Path(tempfile.mkdtemp(prefix='qcap-')); RUN.chmod(0o700)
REPO = Path(__file__).resolve().parents[1]
SHELL_BINARY = Path(os.environ.get('QS_TEST_BINARY', '/usr/bin/qs')).resolve()
COMPOSITOR = Path(shutil.which(os.environ.get('QS_TEST_HYPRLAND', 'Hyprland'))).resolve()
with COMPOSITOR.open('rb') as binary:
    COMPOSITOR_SHA256 = hashlib.file_digest(binary, 'sha256').hexdigest()
env = os.environ.copy()
assert f'/run/user/{os.getuid()}/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Private bus required'
for key in ('DISPLAY', 'XAUTHORITY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'DESKTOP_STARTUP_ID', 'XDG_ACTIVATION_TOKEN', 'QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
    env.pop(key, None)
env.update(HOME=str(OUT/'home'), XDG_CONFIG_HOME=str(OUT/'config'), XDG_STATE_HOME=str(OUT/'state'), XDG_CACHE_HOME=str(OUT/'cache'), XDG_DATA_HOME=str(OUT/'data'), XDG_RUNTIME_DIR=str(RUN), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_NO_XDG_DESKTOP_PORTAL='1', XDG_CURRENT_DESKTOP='test', XDG_SESSION_TYPE='wayland', NO_AT_BRIDGE='1', BROWSER='/usr/bin/false', LIBGL_ALWAYS_SOFTWARE='1', LP_NUM_THREADS='2', AQ_DRM_DEVICES='/nonexistent-test-device')
env.pop('QT_QUICK_BACKEND', None)
subprocess.run(['dbus-update-activation-environment', *[k for k in env if k.startswith(('XDG_', 'QT_', 'WAYLAND', 'HYPRLAND', 'LIBGL', 'AQ_'))], 'HOME', 'BROWSER'], env=env, check=True)
procs=[]; logs=[]; cycle=None; last_state=None
def launch(args,name):
    log=(OUT/(name+'.log')).open('w');logs.append(log)
    proc=subprocess.Popen(args,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);procs.append(proc);return proc
def until(fn, timeout=18):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            value=fn()
            if value:return value
        except (subprocess.SubprocessError,ValueError):pass
        time.sleep(.07)
    raise AssertionError('Timeout: '+str(OUT))
def ctl(*args):return subprocess.check_output(['hyprctl',*args],env=env,text=True,timeout=4)
try:
    shell=OUT/'config/quickshell/ii'
    shutil.copytree(Path(os.environ.get('QS_CAPTURE_ROOT',REPO/'dots/.config/quickshell/ii')),shell)
    if os.environ.get('QS_CAPTURE_BASELINE'):
        shutil.copy2(os.environ['QS_CAPTURE_BASELINE'],shell/'services/HyprlandData.qml')
    p=shell/'modules/common/Directories.qml'
    p.write_text(p.read_text().split('    // Cleanup on init')[0]+'}\n')
    p=shell/'modules/ii/overview/Overview.qml'
    p.write_text(p.read_text().replace('    id: overviewScope', '    id: overviewScope\n    property alias fixturePanel: panelWindow\n    property alias fixtureLoader: overviewLoader', 1))
    config=OUT/'config/illogical-impulse/config.json';config.parent.mkdir(parents=True)
    config.write_text(json.dumps({'overview':{'columns':8,'rows':4,'scale':.12},'resources':{'updateInterval':1000,'historyLength':60},'hacks':{'arbitraryRaceConditionDelay':100}}))
    entry=shell/'capture-test.qml'
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.overview
ShellRoot {
 id:root
 property int gridCreations:0
 Overview {id:overview}
 Connections {target:overview.fixtureLoader;function onLoaded(){root.gridCreations++}}
 function captures(n) {
  let result=[];
  if(n.hasContent!==undefined && n.captureSource!==undefined) result.push({content:n.hasContent,source:!!n.captureSource,w:n.sourceSize.width,h:n.sourceSize.height,visible:n.visible,itemWidth:n.width,itemHeight:n.height});
  for(const child of n.children ?? []) result=result.concat(captures(child));
  return result;
 }
 IpcHandler {
  target:"test"
  function hideGrid(value:bool):void {overview.fixturePanel.setSearchingText(value ? "fixture" : "")}
  function status():string {return JSON.stringify({ready:Config.ready,shown:GlobalStates.overviewOpen,panelVisible:overview.fixturePanel.visible,panelWidth:overview.fixturePanel.width,panelHeight:overview.fixturePanel.height,gridOpacity:overview.fixtureLoader.item?.opacity,count:HyprlandData.windowList.length,gridCreations:root.gridCreations,gridLoaded:overview.fixtureLoader.item!==null,captures:root.captures(overview.fixturePanel.contentItem)})}
 }
}''')
    client=OUT/'clients.qml'
    client.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id:root;property int count:8
 Variants {model:Array.from({length:root.count},(_,i)=>i);Window {required property var modelData;visible:true;width:333+modelData*13;height:241+modelData*7;title:"Capture fixture "+modelData;color:Qt.hsla(modelData/8,.7,.4,1);Rectangle {anchors.centerIn:parent;width:50;height:50;color:"white";NumberAnimation on rotation {from:0;to:360;duration:3000;loops:Animation.Infinite}}}}
 IpcHandler {target:"clients";function fewer():void {root.count=4}}
}''')
    parent_command=['kwin_wayland','--virtual','--width','1280','--height','720','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--socket','capture-parent']
    launch(parent_command,'kwin')
    until(lambda:(RUN/'capture-parent').exists())
    env.update(WAYLAND_DISPLAY='capture-parent',QT_QPA_PLATFORM='wayland')
    hc=OUT/'hyprland.lua'
    hc.write_text('hl.monitor({output="",mode="1280x720@60",position="auto",scale=1})\nhl.config({debug={disable_logs=false},animations={enabled=false},misc={disable_hyprland_logo=true,disable_splash_rendering=true},input={follow_mouse=0}})\n')
    launch([str(COMPOSITOR),'--config',str(hc)],'hyprland')
    sock=until(lambda:next((RUN/'hypr').glob('*/.socket.sock'),None),timeout=60)
    env['HYPRLAND_INSTANCE_SIGNATURE']=sock.parent.name
    env['WAYLAND_DISPLAY']=until(lambda:next((p.name for p in RUN.glob('wayland-*') if not p.name.endswith('.lock')),None))
    until(lambda:json.loads(ctl('-j','monitors')))
    if os.environ.get('QS_CAPTURE_PROTOCOL_ONLY'):
        result=subprocess.run([os.environ['QS_CAPTURE_PROBE']],env=env,capture_output=True,text=True,timeout=12)
        record={'status':'pass' if result.returncode==0 else 'failed','exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'compositor':str(COMPOSITOR),'compositor_sha256':COMPOSITOR_SHA256,'output':str(OUT)}
        (OUT/'result.json').write_text(json.dumps(record,indent=2));print(json.dumps(record),flush=True)
        raise SystemExit(result.returncode)
    if os.environ.get('QS_CAPTURE_DEBUG'):env['WAYLAND_DEBUG']='1'
    qs=launch([str(SHELL_BINARY),'-p',str(entry)],'overview')
    env.pop('WAYLAND_DEBUG',None)
    apps=launch([str(SHELL_BINARY),'-p',str(client)],'clients')
    def call(method,*args):
        return subprocess.check_output([str(SHELL_BINARY),'-p',str(entry),'ipc','call','test',method,*args],env=env,text=True,stderr=subprocess.DEVNULL,timeout=4).strip()
    def status():
        global last_state
        last_state=json.loads(call('status'))
        return last_state
    def show(opened):
        subprocess.run([str(SHELL_BINARY),'-p',str(entry),'ipc','call','search','open' if opened else 'close'],
                       env=env,check=True,stdout=subprocess.DEVNULL,timeout=4)
    def all_previews_ready():
        current=status()
        return current if len(current['captures'])==current['count'] and current['count']>0 and all(c['content'] for c in current['captures']) else None
    until(lambda:status()['count']==8)
    first=None
    for cycle in range(30):
        show(True)
        state=until(all_previews_ready,timeout=10)
        if first is None:first=state
        assert qs.poll() is None
        if cycle==5:
            call('hideGrid','true')
            hidden=until(lambda:(s if all(not c['source'] and not c['content'] for c in s['captures']) else None) if (s:=status()) else None)
            assert hidden['captures'], 'Hiding should retain the widget while releasing captures'
            call('hideGrid','false')
            until(all_previews_ready)
        if cycle==10:
            subprocess.check_call([str(SHELL_BINARY),'-p',str(client),'ipc','call','clients','fewer'],env=env,stdout=subprocess.DEVNULL)
            until(lambda:status()['count']==4)
        if cycle%5==0:
            ctl('dispatch','hl.dsp.focus({workspace="2"})')
            ctl('dispatch','hl.dsp.focus({workspace="1"})')
        show(False);time.sleep(.08)
        closed=status()
        assert all(not c['source'] and not c['content'] for c in closed['captures']), closed
    warm=status()
    assert warm['gridCreations']==1 and warm['gridLoaded'] and len(warm['captures'])==4,warm
    until(lambda:not status()['gridLoaded'])
    assert hashlib.sha256(COMPOSITOR.read_bytes()).hexdigest()==COMPOSITOR_SHA256, 'Compositor changed during test'
    result={'status':'pass','cycles':30,'shell_binary':str(SHELL_BINARY),'first':first,'warm':warm,'last':status(),'pid':qs.pid,'compositor':str(COMPOSITOR),'compositor_sha256':COMPOSITOR_SHA256,'output':str(OUT)}
    (OUT/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
except Exception as error:
    failure={'status':'failed','error':str(error),'output':str(OUT),'cycle':cycle,'last_state':last_state,'process_exits':[p.poll() for p in procs]}
    (OUT/'result.json').write_text(json.dumps(failure,indent=2));print(json.dumps(failure),flush=True)
    raise
finally:
    for proc in reversed(procs):
        try:os.killpg(proc.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        if proc.poll() is None:
            try:proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid,signal.SIGKILL);proc.wait()
    for log in logs:log.close()
