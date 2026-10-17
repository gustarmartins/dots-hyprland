#!/usr/bin/env python3
"""Real EasyEffects helper/service/tiles on private sockets, PipeWire, X11 and D-Bus.
Run: xvfb-run -a -s '-screen 0 900x400x24' dbus-run-session -- python3 tests/easyeffects_integration.py
"""
import json
import os
from pathlib import Path
import shutil
import socketserver
import subprocess
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parents[1]
BINARY = os.environ.get('QS_TEST_BINARY', 'qs')
OUT = Path(tempfile.mkdtemp(prefix='qs-ee-check-'))
CONFIG = OUT / 'config/quickshell/ii'
shutil.copytree(REPO / 'dots/.config/quickshell/ii', CONFIG)
RUNTIME = OUT / 'runtime'
RUNTIME.mkdir(mode=0o700)
BIN = OUT / '.local/bin'
BIN.mkdir(parents=True)
shutil.copy2(REPO / 'dots/.local/bin/easyeffects-qs', BIN / 'easyeffects-qs')
# The real helper's automatic-profile check stays inside this fixture.
for name in ['systemctl', 'easyeffects']:
    p = BIN / name
    p.write_text('#!/bin/sh\n' + (f': > "{OUT / "unexpected-start"}"\n' if name == 'easyeffects' else '') + 'exit 3\n')
    p.chmod(0o755)
presets = OUT / 'data/easyeffects/output'
presets.mkdir(parents=True)
(presets / 'Fixture preset.json').write_text('{}')
prefs = OUT / 'config/illogical-impulse/config.json'
prefs.parent.mkdir(parents=True)
prefs.write_text(json.dumps({'audio': {'protection': {'enable': False}}}))
# No global shortcuts, notification actions or production temp cleanup.
(CONFIG / 'GlobalStates.qml').write_text('''pragma Singleton
import Quickshell
Singleton { property bool sidebarRightOpen: false }
''')
p = CONFIG / 'modules/common/Directories.qml'
s = p.read_text()
p.write_text(s[:s.index('    // Cleanup on init')] + '}\n')

state_lock = threading.Lock()
server_state = {'bypassed': False, 'shows': 0, 'writes': [], 'invalid': False, 'delay': 0}
slow_read_started = threading.Event()

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        command = self.rfile.readline().decode().strip()
        reply = ''
        delay = 0
        with state_lock:
            if command == 'get_global_bypass':
                reply = 'invalid' if server_state['invalid'] else '1' if server_state['bypassed'] else '2'
                delay = server_state['delay']
                server_state['delay'] = 0
            elif command == 'get_last_loaded_preset:output':
                reply = 'Fixture preset'
            elif command.startswith('global_bypass:'):
                server_state['bypassed'] = command.endswith(':1')
                server_state['writes'].append(server_state['bypassed'])
            elif command == 'show_window':
                server_state['shows'] += 1
            else:
                raise AssertionError(command)
        if delay:
            slow_read_started.set()
            time.sleep(delay)
        if reply:
            self.wfile.write((reply + '\n').encode())

class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

server = Server(str(RUNTIME / 'EasyEffectsServer'), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

entry = CONFIG / 'shell.qml'
entry.write_text('''//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles as Models
import qs.modules.ii.sidebarRight.quickToggles.androidStyle
import "modules/ii/sidebarRight/quickToggles/classicStyle" as Classic
ApplicationWindow {
 id: root; visible: true; width: 640; height: 220; x: 0; y: 0; color: "#141313"
 property bool expanded: true
 Models.AudioToggle { id: outputToggle }
 Models.MicToggle { id: inputToggle }
 AndroidEasyEffectsToggle {
  id: tile; x: 16; y: 16; buttonIndex: 0; buttonData: ({type:"easyEffects"})
  expandedSize: root.expanded; baseCellWidth: 104; baseCellHeight: 64
  cellSpacing: 8; cellSize: root.expanded ? 2 : 1
 }
 Classic.EasyEffectsToggle { id: classic; x: 290; y: 50 }
 function findIcon() {
  let queue=[tile]; let seen=new Set();
  while(queue.length) {
   let n=queue.shift(); if(!n || seen.has(n)) continue; seen.add(n);
   if(n.objectName==="easyEffectsProcessingIcon") return n;
   for(let c of n.children || []) queue.push(c);
   if(n.contentItem) queue.push(n.contentItem);
  }
  return null;
 }
 function rect(item) {
  let p=item.mapToItem(root.contentItem,0,0);
  return {x:p.x,y:p.y,width:item.width,height:item.height};
 }
 IpcHandler {
  target: "test"
  function status(): string {
   return JSON.stringify({active:EasyEffects.active,bypassed:EasyEffects.bypassed,
    processing:EasyEffects.processing,known:EasyEffects.stateKnown,busy:EasyEffects.busy,
    error:EasyEffects.error,preset:EasyEffects.preset,toggled:tile.toggled,
    classic:classic.toggled,enabled:tile.enabled,label:tile.statusText,
    icon:root.findIcon() ? root.rect(root.findIcon()) : null,tile:root.rect(tile),
    classicRect:root.rect(classic),audioReady:Audio.ready,sink:Audio.sink?.name ?? null,
    source:Audio.source?.name ?? null,volume:Audio.value,
    outputAvailable:outputToggle.available,inputAvailable:inputToggle.available,
    outputToggled:outputToggle.toggled,inputToggled:inputToggle.toggled});
  }
  function compact(value: bool): void { root.expanded=!value; }
  function refresh(): void { EasyEffects.fetchActiveState(); }
  function audioControls(): void { Audio.toggleMute();Audio.toggleMicMute();Audio.incrementVolume();Audio.decrementVolume(); }
  function volume(value: real): void { Audio.sink.audio.volume=value; }
  function protect(enabled: bool): void { Config.options.audio.protection.enable=enabled; }
  function capture(path: string): void { tile.grabToImage(r=>r.saveToFile(path)); }
 }
}
''')
env = os.environ.copy()
for key in ['WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
    env.pop(key, None)
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
env.pop('PIPEWIRE_REMOTE', None)
env.update(HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'), XDG_STATE_HOME=str(OUT / 'state'),
    XDG_DATA_HOME=str(OUT / 'data'), XDG_CACHE_HOME=str(OUT / 'cache'), XDG_RUNTIME_DIR=str(RUNTIME),
    PATH=str(BIN) + ':' + env['PATH'], QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software',
    PIPEWIRE_RUNTIME_DIR=str(RUNTIME), QT_NO_XDG_DESKTOP_PORTAL='1')
pipeconf = OUT / 'pipewire.conf'
pipeconf.write_text('''context.properties = { core.daemon = true core.name = pipewire-0 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
 { name = libpipewire-module-protocol-native }
 { name = libpipewire-module-metadata }
 { name = libpipewire-module-spa-node-factory }
 { name = libpipewire-module-client-node }
 { name = libpipewire-module-access }
 { name = libpipewire-module-adapter }
 { name = libpipewire-module-link-factory }
]
context.objects = [ { factory = metadata args = { metadata.name = default } } ]
''')
logs = []
processes = []
checks = []

def launch(args, name):
    log = (OUT / (name + '.log')).open('w'); logs.append(log)
    p = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(p)
    return p

def until(fn, timeout=12):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            result = fn()
            if result: return result
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError): pass
        time.sleep(.03)
    raise AssertionError('Timed out: ' + str(OUT))

def call(method, *args):
    value = subprocess.check_output([BINARY,'-p',str(entry),'ipc','call','test',method,*map(str,args)],
        env=env,stderr=subprocess.DEVNULL,text=True,timeout=3).strip()
    return json.loads(value) if value else None

def status(): return call('status')
def settled():
    def ready():
        s = status()
        return s if s['known'] and not s['busy'] else None
    return until(ready)
def check(name, condition):
    assert condition, (name, status())
    checks.append(name)

def click(part, button=1, body=False):
    r = status()[part]
    x = r['x'] + r['width'] * (.87 if body else .5)
    y = r['y'] + r['height'] * (.83 if body else .5)
    subprocess.run(['xdotool','mousemove','--sync',str(round(x)),str(round(y)),'click',str(button)],env=env,check=True)
    time.sleep(.12)

def fake(**values):
    with state_lock: server_state.update(values)

def create(name, kind):
    subprocess.check_call(['pw-cli','create-node','adapter',
        f'{{ factory.name = support.null-audio-sink node.name = {name} media.class = Audio/{kind} audio.position = [ FL FR ] object.linger = true }}'],env=env,stdout=subprocess.DEVNULL)
    def locate():
        objs=json.loads(subprocess.check_output(['pw-dump'],env=env))
        return next((o['id'] for o in objs if o.get('info',{}).get('props',{}).get('node.name')==name),None)
    return until(locate)

def default(kind, name):
    subprocess.check_call(['pw-metadata','-n','default','0','default.audio.'+kind,json.dumps({'name':name}),'Spa:String:JSON'],env=env,stdout=subprocess.DEVNULL)

try:
    pw = launch(['pipewire','-c',str(pipeconf)], 'pipewire')
    until(lambda: (RUNTIME / 'pipewire-0').exists())
    shell = launch([BINARY,'-p',str(entry),'--no-color'], 'ui')
    s = settled()
    check('processing state drives both tile styles', s['toggled'] and s['classic'])
    check('no hardware devices on the private server', not s['audioReady'])
    check('absent devices have unavailable, inactive tiles', not s['outputAvailable'] and not s['inputAvailable'] and not s['outputToggled'] and not s['inputToggled'])
    call('audioControls')
    for compact in [False, True]:
        call('compact', str(compact).lower()); time.sleep(.1)
        shows = server_state['shows']; writes = len(server_state['writes'])
        click('icon'); s = settled()
        check(f'icon disables processing, size={compact}', s['active'] and s['bypassed'] and not s['toggled'] and not s['classic'])
        check(f'icon has exactly one action, size={compact}', len(server_state['writes'])==writes+1 and server_state['shows']==shows)
        click('tile', body=True)
        until(lambda: server_state['shows']==shows+1)
        check(f'body opens app without changing processing, size={compact}', server_state['bypassed'])
        click('icon'); s = settled()
        check(f'icon enables processing, size={compact}', s['toggled'] and s['classic'])
        click('tile', button=3, body=True)
        until(lambda: server_state['shows']==shows+2)
        check(f'right click opens app, size={compact}', not server_state['bypassed'])
    click('classicRect'); check('classic icon disables processing', settled()['bypassed'])
    # External change while the closed panel retains an old cached state.
    fake(bypassed=False)
    click('icon'); check('toggle reads current server state instead of cached QML', settled()['bypassed'])
    # An old status response completes after the action's confirmed state.
    fake(bypassed=False); call('refresh'); until(lambda: status()['processing'])
    slow_read_started.clear(); fake(delay=.65); call('refresh')
    assert slow_read_started.wait(3)
    click('icon'); check('action publishes confirmed bypass', settled()['bypassed'])
    time.sleep(.8)
    check('late pre-action status cannot overwrite the result', status()['bypassed'])
    fake(invalid=True); call('refresh')
    until(lambda: not status()['known'])
    check('invalid status is explicit and retains preset', status()['error'] and status()['preset']=='Fixture preset')
    click('icon'); until(lambda: not status()['busy'])
    check('invalid state does not start or change effects', server_state['bypassed'] and not (OUT/'unexpected-start').exists())
    fake(invalid=False); call('refresh'); settled()
    for cycle in range(4):
        for kind in ['sink','source']:
            name=f'fixture-{kind}-{cycle}'
            node=create(name,kind.capitalize()); default(kind,name)
            until(lambda: status()[kind]==name)
            until(lambda: status()['outputAvailable' if kind=='sink' else 'inputAvailable'])
            if kind=='sink': until(lambda: status()['audioReady'])
            call('audioControls')
            subprocess.check_call(['pw-cli','destroy',str(node)],env=env,stdout=subprocess.DEVNULL)
            until(lambda: status()[kind] is None)
            until(lambda: not status()['outputAvailable' if kind=='sink' else 'inputAvailable'])
            call('audioControls')
        check(f'sink/source removal and restoration {cycle+1}', not status()['audioReady'])
    a=create('quiet-output','Sink'); default('sink','quiet-output')
    until(lambda: status()['audioReady']); call('volume',.2)
    until(lambda: abs(status()['volume']-.2)<.01)
    call('protect','true'); call('volume',.3)
    until(lambda: abs(status()['volume']-.3)<.01)
    b=create('replacement-output','Sink'); default('sink','replacement-output')
    until(lambda: status()['sink']=='replacement-output' and status()['audioReady'])
    time.sleep(.2)
    check('replacement output keeps its own volume with protection enabled', abs(status()['volume']-1)<.01)
    call('protect','false')
    for node in [a,b]: subprocess.check_call(['pw-cli','destroy',str(node)],env=env,stdout=subprocess.DEVNULL)
    until(lambda: not status()['audioReady'])
    node=create('before-restart','Sink'); default('sink','before-restart')
    until(lambda: status()['audioReady'])
    pw.terminate(); pw.wait(timeout=5)
    until(lambda: not status()['audioReady']); call('audioControls')
    pw=launch(['pipewire','-c',str(pipeconf)],'pipewire-restarted')
    until(lambda: (RUNTIME/'pipewire-0').exists())
    node=create('after-restart','Sink'); default('sink','after-restart')
    until(lambda: status()['sink']=='after-restart' and status()['audioReady'])
    check('PipeWire server reconnects without restarting Quickshell', shell.poll() is None)
    fake(bypassed=False)
    subprocess.check_call(['pw-cli','destroy',str(node)],env=env,stdout=subprocess.DEVNULL)
    until(lambda: status()['processing'])
    check('device change refreshes EasyEffects while panel is closed', status()['toggled'])
    call('compact','false')
    subprocess.check_call(['xdotool','mousemove','610','190'],env=env)
    time.sleep(.2); call('capture', OUT/'widget-on.png'); time.sleep(.3)
    click('icon'); settled()
    subprocess.check_call(['xdotool','mousemove','610','190'],env=env)
    time.sleep(.2); call('capture', OUT/'widget-off.png'); time.sleep(.3)
    errors=[l for l in (OUT/'ui.log').read_text().splitlines() if any(t in l for t in ['ERROR','TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign'])]
    check('no QML state or mouse-handler errors', not errors)
    result={'passed':True,'checks':checks,'output':str(OUT)}
    (OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
finally:
    for p in reversed(processes):
        if p.poll() is None:
            p.terminate()
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired: p.kill();p.wait()
    server.shutdown();server.server_close()
    for log in logs: log.close()
    print('Evidence:',OUT)
