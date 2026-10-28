#!/usr/bin/env python3
"""Clock reload/availability regression with a private Night Light helper.

Run: xvfb-run -a dbus-run-session -- python3 tests/quickshell_clock_lifecycle.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix='qs-clock-errors-'))
shell = OUT / 'ii'
shutil.copytree(REPO / 'dots/.config/quickshell/ii', shell)
for directory in ('runtime', 'config/illogical-impulse', '.local/bin', 'cache', 'state', 'data'):
    (OUT / directory).mkdir(parents=True, mode=0o700)
(OUT / 'config/illogical-impulse/config.json').write_text(json.dumps({'light': {'night': {'automatic': False}}, 'time': {'format': 'HH:mm:ss'}}))
p = shell / 'modules/common/Directories.qml'
p.write_text(p.read_text().split('    // Cleanup on init')[0] + '}\n')
helper = OUT / '.local/bin/hyprsunsetctl'
helper.write_text('''#!/usr/bin/python3
import sys
from pathlib import Path
with (Path.home()/'calls').open('a') as f: f.write(' '.join(sys.argv[1:])+'\\n')
if sys.argv[1:] == ['gamma']: print(100)
elif sys.argv[1:] == ['identity', 'get']: print('true')
else: raise SystemExit(2)
''')
helper.chmod(0o755)
(shell / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 id: root
 property var savedClock
 IpcHandler {
  target: "test"
  function status(): string { return JSON.stringify({time:DateTime.time,uptime:DateTime.uptime,hour:Hyprsunset.clockHour,minute:Hyprsunset.clockMinute}); }
  function clearClock(): void { root.savedClock=DateTime.clock; DateTime.clock=null; Hyprsunset.reEvaluate(); Hyprsunset.ensureState(); }
  function restoreClock(): void { DateTime.clock=root.savedClock; }
  function reload(): void { Quickshell.reload(false); }
 }
}
''')
env = dict(os.environ, HOME=str(OUT), XDG_CONFIG_HOME=str(OUT / 'config'),
           XDG_CACHE_HOME=str(OUT / 'cache'), XDG_STATE_HOME=str(OUT / 'state'),
           XDG_DATA_HOME=str(OUT / 'data'), XDG_RUNTIME_DIR=str(OUT / 'runtime'),
           QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software', WAYLAND_DISPLAY='',
           HYPRLAND_INSTANCE_SIGNATURE='', XDG_CURRENT_DESKTOP='test')
for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
    env.pop(key, None)
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME',
                'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR', 'DISPLAY', 'QT_QPA_PLATFORM',
                'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP'], env=env, check=True)

def call(method):
    output = subprocess.check_output(['qs', '-p', str(shell), 'ipc', 'call', 'test', method],
                                     env=env, stderr=subprocess.DEVNULL, text=True, timeout=3).strip()
    return json.loads(output) if output else None

def wait_ready():
    for _ in range(100):
        try:
            state = call('status')
            if state['hour'] >= 0 and state['time'].count(':') == 2 and state['uptime'] != '0h, 0m':
                return state
        except (subprocess.CalledProcessError, ValueError, TypeError):
            pass
        time.sleep(.05)
    raise AssertionError(log_path.read_text())

log_path = OUT / 'ui.log'
with log_path.open('w') as log:
    process = subprocess.Popen(['qs', '-p', str(shell), '--no-color'], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        state = wait_ready()
        assert state['time'].count(':') == 2, state
        for _ in range(3):
            call('clearClock'); state = call('status')
            assert state['hour'] == -1 and state['minute'] == -1, state
            call('restoreClock'); assert call('status')['hour'] >= 0
            call('reload'); time.sleep(.1)
            wait_ready()
        time.sleep(.2)
    finally:
        process.terminate(); process.wait(timeout=5)
output = log_path.read_text()
bad = [line for line in output.splitlines() if any(word in line for word in
       ('ERROR:', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Unable to assign', 'of null'))]
assert not bad, '\n'.join(bad)
calls = (OUT / 'calls').read_text().splitlines()
assert calls and set(calls) <= {'gamma', 'identity get'}, calls
print(json.dumps({'status': 'passed', 'artifacts': str(OUT),
                  'checks': ['custom time format', 'uptime readback', 'clock disappears and returns',
                             'three hot reloads', 'no Night Light writes']}))
