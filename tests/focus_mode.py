#!/usr/bin/env python3
"""Real QML/file notifications and explicit actions in a private session."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cryod-focus-qml-') as directory:
    root = Path(directory)
    for name in ('shell/services', 'run', 'home', 'cache', 'runtime'):
        (root / name).mkdir(parents=True, mode=0o700)
    shutil.copy2(repo / 'dots/.config/quickshell/ii/services/FocusMode.qml', root / 'shell/services/FocusMode.qml')
    helper = root / 'helper'
    helper.write_text('''#!/usr/bin/python3
import json,sys,time,os
from pathlib import Path
root=Path(__file__).parent
calls=root/'calls'
with calls.open('a') as f:f.write(sys.argv[1]+'\\n')
if len(calls.read_text().splitlines()) == 3:
 print('fixture refusal',file=sys.stderr);raise SystemExit(1)
enabled=sys.argv[1]=='on'
value={'timestamp':time.time(),'native':{'focus_performance':dict(schema=1,uid=1000,available=True,enabled=enabled,active=enabled,reason='focused-cpu-boost' if enabled else 'off')}}
temp=root/'run/new';temp.write_text(json.dumps(value));os.replace(temp,root/'run/status.json')
''')
    helper.chmod(0o755)
    (root / 'shell/shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property int step: 0
 Component.onCompleted: { FocusMode.runtimePath = RUNTIME; FocusMode.executable = HELPER; }
 Timer {
  interval: 150; repeat: true; running: true
  onTriggered: {
   step++;
   if (step === 3) FocusMode.setEnabled(true);
   if (step === 8) {
    if (!FocusMode.enabled || !FocusMode.active || FocusMode.busy) { console.log("FAIL on"); Qt.quit(); return; }
    FocusMode.setEnabled(false);
   }
   if (step === 13) {
    if (FocusMode.enabled || FocusMode.active) { console.log("FAIL off"); Qt.quit(); return; }
    FocusMode.setEnabled(true);
   }
   if (step === 20) {
    if (FocusMode.enabled || !FocusMode.error.includes("fixture refusal")) { console.log("FAIL refusal"); Qt.quit(); return; }
    console.log("FOCUS_QML_PASS");Qt.quit();
   }
  }
 }
}
'''.replace('RUNTIME', json.dumps(str(root / 'run'))).replace('HELPER', json.dumps(str(helper))))
    env = dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'home/config'),
               XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'),
               QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', WAYLAND_DISPLAY='')
    for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
        env.pop(key, None)
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root / 'shell')],
                            env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and 'FOCUS_QML_PASS' in output and 'FAIL ' not in output, output
    assert (root / 'calls').read_text().splitlines() == ['on', 'off', 'on']
    print('PASS: file-driven QML On/Off, actual readback, surfaced refusal, no polling subprocesses')
