#!/usr/bin/env python3
"""Exercise production Hyprland snapshots with private IPC and no real windows.

Run under dbus-run-session. --baseline FILE also measures the pre-fix service.
All client titles, configuration, IPC sockets and process state are fixtures.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'dots/.config/quickshell/ii'
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path)
parser.add_argument('--output', type=Path)
parser.add_argument('--allow-unbatched', action='store_true')
args = parser.parse_args()
output = args.output or Path(tempfile.mkdtemp(prefix='qs-snapshots-'))
output.mkdir(parents=True, exist_ok=True)
runtime = Path(tempfile.mkdtemp(prefix='qsp-'))
socket_dir = runtime / 'hypr/test'
socket_dir.mkdir(parents=True)
env = os.environ.copy()
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
for key in ('WAYLAND_DISPLAY', 'DISPLAY'):
    env.pop(key, None)
env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='test',
           QT_QPA_PLATFORM='offscreen', HOME=str(output/'home'),
           XDG_CONFIG_HOME=str(output/'config'), XDG_DATA_HOME=str(output/'data'),
           XDG_STATE_HOME=str(output/'state'), XDG_CACHE_HOME=str(output/'cache'),
           QT_NO_XDG_DESKTOP_PORTAL='1', NO_AT_BRIDGE='1', XDG_CURRENT_DESKTOP='')
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME',
                'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR',
                'QT_QPA_PLATFORM', 'QT_NO_XDG_DESKTOP_PORTAL', 'NO_AT_BRIDGE',
                'XDG_CURRENT_DESKTOP', 'WAYLAND_DISPLAY=', 'DISPLAY='], env=env, check=True)
state = {'generation': 0, 'count': 24, 'focused': 1, 'width': 640}
requests = []
stopping = threading.Event()


def listen(name):
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(socket_dir/name))
    server.listen()
    server.settimeout(.1)
    return server


def data():
    spaces = [{'id': n, 'address': str(n), 'name': str(n), 'type': 'normal',
               'monitor': 'TEST-1', 'monitorID': 0, 'hasfullscreen': False} for n in (1, 2)]
    windows = [{'address': hex(0x100+n), 'workspace': spaces[n % 2], 'monitor': 0,
                'title': f'fixture-{n}-{state["generation"]}', 'class': 'test',
                'pid': 1000+n, 'size': [state['width'], 480], 'at': [0, 0],
                'mapped': True, 'hidden': False, 'fullscreen': 0, 'fullscreenClient': 0}
               for n in range(state['count'])]
    monitors = [{'id': 0, 'name': 'TEST-1', 'width': 1920, 'height': 1080,
                 'scale': 1, 'focused': True, 'reserved': [0, 0, 0, 0],
                 'activeWorkspace': spaces[state['focused']-1]}]
    return {'j/status': {'configProvider': 'lua'}, 'j/monitors': monitors,
            'j/workspaces': spaces, 'j/clients': windows,
            'j/activewindow': windows[0] if windows else {}, 'j/layers': {}}


def serve(server):
    while not stopping.is_set():
        try:
            connection, _ = server.accept()
        except socket.timeout:
            continue
        with connection:
            request = connection.recv(65536).decode()
            requests.append(request)
            connection.sendall(json.dumps(data().get(request, {})).encode())


def until(fn, timeout=8):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        try:
            value = fn()
            if value:
                return value
        except (json.JSONDecodeError, subprocess.SubprocessError, socket.timeout):
            pass
        time.sleep(.025)
    raise AssertionError('Timed out; logs: '+str(output))


request_server, event_server = listen('.socket.sock'), listen('.socket2.sock')
worker = threading.Thread(target=serve, args=(request_server,), daemon=True)
worker.start()
results = {}
try:
    variants = ([('before', args.baseline)] if args.baseline else []) + [('after', SOURCE/'services/HyprlandData.qml')]
    for label, source in variants:
        state.update(generation=0, count=24, focused=1, width=640)
        shell = output/label
        (shell/'services').mkdir(parents=True)
        (shell/'modules/common/functions').mkdir(parents=True)
        shutil.copy2(source, shell/'services/HyprlandData.qml')
        shutil.copy2(SOURCE/'modules/common/functions/WorkspaceIdentity.js', shell/'modules/common/functions/WorkspaceIdentity.js')
        (shell/'services/qmldir').write_text('singleton HyprlandData 1.0 HyprlandData.qml\n')
        fixture = shell/'shell.qml'
        fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "services"
ShellRoot {
 id: root
 property int changes: 0
 property double lastBeat: Date.now()
 property double maxGap: 0
 property string consumer: JSON.stringify(HyprlandData.windowByAddress)
 Timer { interval: 16; repeat: true; running: true; onTriggered: {
  let now=Date.now(); root.maxGap=Math.max(root.maxGap,now-root.lastBeat); root.lastBeat=now;
 } }
 Connections { target: HyprlandData; function onWindowListChanged() { root.changes++; } }
 IpcHandler {
  target: "test"
  function reset(): void { root.changes=0; root.maxGap=0; }
  function refresh(): void { HyprlandData.updateAll(); }
  function trackLayers(enabled: bool): void { HyprlandData.trackLayerEvents=enabled; }
  function state(): string { return JSON.stringify({changes:root.changes,gap:root.maxGap,
   windows:HyprlandData.windowList.map(w=>({address:w.address,title:w.title,width:w.size[0]})),
   focused:HyprlandData.activeWorkspace?.id ?? -1,
   workspaces:HyprlandData.workspaceIds, monitors:HyprlandData.monitors.map(m=>m.activeWorkspace.id),
   largest:HyprlandData.biggestWindowForWorkspace(1)?.address,
   windowCounts:HyprlandData.windowStatsByWorkspace ? [1,2].map(id=>HyprlandData.windowStatsByWorkspace[id]?.count ?? 0) : [],
   consumerLength:root.consumer.length}); }
 }
}
''')
        log = (output/(label+'.log')).open('w')
        process = subprocess.Popen(['qs', '-p', str(fixture)], env=env, stdout=log, stderr=subprocess.STDOUT)
        event_client = None
        try:
            event_client, _ = until(lambda: event_server.accept())

            def call(action, *values):
                return subprocess.check_output(['qs', '-p', str(fixture), 'ipc', 'call', 'test', action, *values],
                                               env=env, text=True, stderr=subprocess.DEVNULL, timeout=3).strip()

            def read():
                return json.loads(call('state'))

            until(lambda: len(read()['windows']) == 24)
            time.sleep(.15)
            call('reset')
            batches = []
            for generation in range(1, 9):
                state['generation'] = generation
                previous = read()['changes']
                started = time.monotonic()
                call('refresh')
                current = until(lambda: (s if all(w['title'].endswith('-'+str(generation)) for w in s['windows']) else None)
                                if (s := read()) else None)
                batches.append({'updates': current['changes']-previous,
                                'elapsed_ms': round((time.monotonic()-started)*1000, 2)})
            # Title-only activity must use the native title, including commas,
            # without fetching all clients to update a status spinner.
            time.sleep(.3)
            request_start = len(requests)
            state['generation'] = 'title,event'
            for index in range(state['count']):
                event_client.sendall(('windowtitlev2>>'+format(0x100+index,'x')
                                      +f',fixture-{index}-title,event\n').encode())
            title_state = until(lambda: (s if all(w['title'].endswith('-title,event') for w in s['windows'])
                                         else None) if (s := read()) else None)
            title_requests = requests[request_start:].count('j/clients')
            # Model removals and geometry updates must survive coalescing.
            state.update(count=7, width=900, focused=2)
            for index in range(7, 24):
                event_client.sendall(('closewindow>>'+format(0x100+index,'x')+'\n').encode())
            event_client.sendall(b'workspace>>2\nworkspacev2>>2,2\n')
            call('refresh')
            final = until(lambda: (s if len(s['windows']) == 7 and all(w['width'] == 900 for w in s['windows'])
                                   and s['monitors'] == [2] else None) if (s := read()) else None)
            if label == 'after' and not args.allow_unbatched:
                assert max(b['updates'] for b in batches) <= 2, batches
                assert title_requests == 0, requests[request_start:]
                first_on_one = next(w['address'] for w in final['windows'] if int(w['address'],16) % 2 == 0)
                assert final['windowCounts'] == [4,3] and final['largest'] == first_on_one, final
                time.sleep(.15)
                start = len(requests)
                event_client.sendall(b'openlayer>>quickshell:overview\ncloselayer>>quickshell:overview\n')
                time.sleep(.2)
                assert 'j/layers' not in requests[start:], requests[start:]
                call('trackLayers','true')
                event_client.sendall(b'openlayer>>fixture-selector\n')
                until(lambda: 'j/layers' in requests[start:])
            assert final['workspaces'] == [1, 2], final
            results[label] = {'batches': batches, 'title_client_requests': title_requests,
                              'final': final}
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            if event_client:
                event_client.close()
            log.close()
        errors = (output/(label+'.log')).read_text()
        assert not any(x in errors for x in ('ReferenceError', 'TypeError', 'Binding loop detected')), errors[-2000:]
    (output/'result.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps({'output':str(output), 'results':results}, indent=2))
finally:
    stopping.set()
    worker.join(timeout=1)
    request_server.close()
    event_server.close()
    shutil.rmtree(runtime)
