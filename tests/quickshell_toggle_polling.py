#!/usr/bin/env python3
"""Retained status models must stop polling while hidden and refresh on show.

Run under dbus-run-session. All helper commands are harmless fixture scripts.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT/'dots/.config/quickshell/ii/modules/common/models/quickToggles'
NAMES = ['MemoryModeToggle', 'BuildCacheToggle', 'GpuMemoryToggle', 'ZramAlgoToggle',
         'ZramWritebackToggle', 'LsfgToggle']
out = Path(tempfile.mkdtemp(prefix='qs-polling-'))
runtime = out/'run'
runtime.mkdir(mode=0o700)
shell = out/'shell'
models = shell/'modules/common/models/quickToggles'
models.mkdir(parents=True)
for name in ['QuickToggleModel', *NAMES]:
    # Keep the production model logic; substitute only its unused UI imports
    # and the translation dependency so this fixture loads no real services.
    lines = []
    for line in (MODELS/(name+'.qml')).read_text().splitlines():
        if line == 'import qs.services':
            lines.append('import "../../../../services"')
        elif not line.startswith('import qs'):
            lines.append(line)
    (models/(name+'.qml')).write_text('\n'.join(lines)+'\n')
for directory in ['services', 'modules/common', 'modules/common/functions', 'modules/common/widgets']:
    folder = shell/directory
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'qmldir').write_text('')
(shell/'services/qmldir').write_text('singleton Translation 1.0 Translation.qml\n')
(shell/'services/Translation.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function tr(text) { return text; } }\n')
bindir = out/'home/.local/bin'
bindir.mkdir(parents=True)
counter = out/'calls.jsonl'
helper = bindir/'fixture-helper'
helper.write_text('''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
with Path(os.environ['POLL_TEST_CALLS']).open('a') as f:
 f.write(json.dumps({'name':Path(sys.argv[0]).name,'args':sys.argv[1:],'time':time.monotonic()})+'\\n')
if Path(sys.argv[0]).name == 'hyprctl': print('[{"name":"DP-1","refreshRate":144}]')
else: print('off')
''')
helper.chmod(0o755)
for name in ['memory-mode.sh', 'build-cache-mode', 'memory-tools.sh', 'zram-algo-mode.sh', 'hyprctl']:
    (bindir/name).symlink_to(helper)
env = os.environ.copy()
assert '/run/user/' + str(os.getuid()) + '/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
    env.pop(key, None)
env.update(HOME=str(out/'home'), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(out/'config'),
           XDG_DATA_HOME=str(out/'data'), XDG_CACHE_HOME=str(out/'cache'), XDG_STATE_HOME=str(out/'state'),
           QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1', NO_AT_BRIDGE='1',
           XDG_CURRENT_DESKTOP='', PATH=str(bindir)+':'+env['PATH'], POLL_TEST_CALLS=str(counter))
subprocess.run(['dbus-update-activation-environment', 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME',
                'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'QT_QPA_PLATFORM',
                'QT_NO_XDG_DESKTOP_PORTAL', 'NO_AT_BRIDGE', 'XDG_CURRENT_DESKTOP',
                'WAYLAND_DISPLAY=', 'DISPLAY='], env=env, check=True)
fixture = shell/'shell.qml'
fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "modules/common/models/quickToggles"
ShellRoot {
 id: root
 property bool shown: false
 MODELS
 IpcHandler {
  target: "test"
  function setShown(shown: bool): void { root.shown=shown; }
  function ready(): bool { return true; }
 }
}
'''.replace('MODELS', '\n'.join(name+' { pollingEnabled: root.shown }' for name in NAMES)))


def call(action, *args):
    result = subprocess.run(['qs', '-p', str(fixture), 'ipc', 'call', 'test', action, *args],
                            env=env, text=True, capture_output=True, timeout=3)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    return result.stdout


def calls():
    return [json.loads(s) for s in counter.read_text().splitlines()] if counter.exists() else []


with (out/'shell.log').open('w') as log:
    process = subprocess.Popen(['qs', '-p', str(fixture)], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic()+8
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise AssertionError((out/'shell.log').read_text())
            try:
                call('ready')
                break
            except subprocess.SubprocessError:
                time.sleep(.05)
        else:
            raise AssertionError('Fixture did not start')
        time.sleep(3.3)
        assert not calls(), calls()
        call('setShown', 'true')
        deadline = time.monotonic()+3
        while len(calls()) < len(NAMES) and time.monotonic() < deadline:
            time.sleep(.05)
        first = calls()
        assert len(first) == len(NAMES), first
        assert {r['name'] for r in first} == {'memory-mode.sh', 'build-cache-mode',
                                             'memory-tools.sh', 'zram-algo-mode.sh', 'hyprctl'}, first
        call('setShown', 'false')
        time.sleep(.2)
        closed = len(calls())
        time.sleep(3.3)
        assert len(calls()) == closed, calls()
        call('setShown', 'true')
        deadline = time.monotonic()+3
        while len(calls()) < closed+len(NAMES) and time.monotonic() < deadline:
            time.sleep(.05)
        assert len(calls()) == closed+len(NAMES), calls()
        print(json.dumps({'hidden_calls':0, 'on_show':len(first), 'after_hidden':len(calls())-closed,
                          'models':NAMES, 'output':str(out)}))
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
    errors = (out/'shell.log').read_text()
    assert not any(s in errors for s in ('ReferenceError', 'TypeError', 'Binding loop detected')), errors
