#!/usr/bin/env python3
"""Exercise the real overview loader on a private X11 display and D-Bus bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='qs-retention-'))
assert f'/run/user/{os.getuid()}/bus' not in os.environ.get('DBUS_SESSION_BUS_ADDRESS',''), 'Private bus required'
shutil.copy2(REPO/'dots/.config/quickshell/ii/modules/ii/overview/OverviewContentLoader.qml',OUT)
for name in ('home','config','cache','state','data','run'):
    (OUT/name).mkdir(mode=0o700)
entry=OUT/'shell.qml'
entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
Window {
 id:root; visible:true; width:200; height:100
 property bool shown:false
 property int oldCreated:0
 property int newCreated:0
 property int ticks:0
 Loader {
  active:root.shown
  sourceComponent: Item {Component.onCompleted:root.oldCreated++}
 }
 OverviewContentLoader {
  id:cached; shown:root.shown
  sourceComponent: Item {Component.onCompleted:root.newCreated++}
 }
 Timer {
  id:burst; interval:60; repeat:true
  onTriggered: {root.shown=!root.shown;root.ticks++;if(root.ticks===30)stop()}
 }
 IpcHandler {
  target:"test"
  function runBurst():void {root.ticks=0;burst.start()}
  function showContent(value:bool):void {root.shown=value}
  function feature(value:bool):void {cached.featureEnabled=value}
  function state():string {return JSON.stringify({oldCreated:root.oldCreated,newCreated:root.newCreated,
    ticks:root.ticks,shown:root.shown,active:cached.active,ready:cached.status===Loader.Ready,
    recent:cached.recentlyShown,hasItem:cached.item!==null})}
 }
}''')
env=os.environ.copy()
for key in ('WAYLAND_DISPLAY','WAYLAND_SOCKET','HYPRLAND_INSTANCE_SIGNATURE','QS_CONFIG_PATH','QS_CONFIG_NAME','XDG_ACTIVATION_TOKEN','DESKTOP_STARTUP_ID'):
    env.pop(key,None)
env.update(HOME=str(OUT/'home'),XDG_CONFIG_HOME=str(OUT/'config'),XDG_CACHE_HOME=str(OUT/'cache'),
           XDG_STATE_HOME=str(OUT/'state'),XDG_DATA_HOME=str(OUT/'data'),XDG_RUNTIME_DIR=str(OUT/'run'),
           QT_QPA_PLATFORM='xcb',QT_QPA_PLATFORMTHEME='',QT_QUICK_BACKEND='software',
           QT_NO_XDG_DESKTOP_PORTAL='1',NO_AT_BRIDGE='1',XDG_CURRENT_DESKTOP='test',BROWSER='/usr/bin/false')
subprocess.run(['dbus-update-activation-environment','HOME','DISPLAY','XDG_CONFIG_HOME','XDG_CACHE_HOME',
                'XDG_STATE_HOME','XDG_DATA_HOME','XDG_RUNTIME_DIR','QT_QPA_PLATFORM','QT_QUICK_BACKEND',
                'QT_NO_XDG_DESKTOP_PORTAL','XDG_CURRENT_DESKTOP','BROWSER'],env=env,check=True)
def call(*args):
    return subprocess.check_output(['/usr/bin/qs','-p',str(entry),'ipc','call','test',*args],env=env,text=True,stderr=subprocess.DEVNULL,timeout=5).strip()
def state():return json.loads(call('state'))
def until(fn,seconds=12):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        assert process.poll() is None, (OUT/'shell.log').read_text()
        try:
            value=fn()
            if value:return value
        except (subprocess.SubprocessError,ValueError):pass
        time.sleep(.07)
    raise AssertionError('Timeout: '+str(OUT))
with (OUT/'shell.log').open('w') as log:
    process=subprocess.Popen(['/usr/bin/qs','-p',str(entry)],env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        until(lambda:state(),60)
        call('runBurst')
        until(lambda:state()['ticks']==30)
        warm=state()
        assert warm['oldCreated']==15 and warm['newCreated']==1, warm
        assert warm['active'] and warm['hasItem'] and not warm['shown'],warm
        until(lambda:not state()['hasItem'])
        assert not state()['active']
        call('showContent','true');until(lambda:state()['ready'])
        assert state()['newCreated']==2
        call('feature','false')
        until(lambda:not state()['hasItem'])
        assert not state()['recent']
        call('showContent','false');call('feature','true')
        assert not state()['active'], 'Enabling while hidden must not start background construction'
        call('showContent','true');until(lambda:state()['ready'])
        result={'status':'pass','warm':warm,'final':state(),'checks':['15 rapid opens create one retained component','idle deadline releases component','feature off releases immediately','reenable while hidden stays idle'],'output':str(OUT)}
        (OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
