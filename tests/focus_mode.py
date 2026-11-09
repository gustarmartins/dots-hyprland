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
    for name in ('shell/services', 'run', 'performance', 'preferences', 'home', 'cache', 'runtime'):
        (root / name).mkdir(parents=True, mode=0o700)
    shutil.copy2(repo / 'dots/.config/quickshell/ii/services/FocusMode.qml', root / 'shell/services/FocusMode.qml')
    helper = root / 'helper'
    helper.write_text('''#!/usr/bin/python3
import json,sys,time,os
from pathlib import Path
root=Path(__file__).parent
calls=root/'calls'
with calls.open('a') as f:f.write(sys.argv[1]+'\\n')
if len(calls.read_text().splitlines()) == 7:
 print('fixture refusal',file=sys.stderr);raise SystemExit(1)
command=sys.argv[1]
path=root/'preferences/performance-1000.json'
hardware=json.loads(path.read_text())['hardware'] if path.exists() else False
previous=json.loads((root/'run/status.json').read_text())['native']['focus_performance'] if (root/'run/status.json').exists() else {}
enabled=previous.get('enabled',False) if command.startswith('hardware-') else command=='on'
if command.startswith('hardware-'):hardware=command=='hardware-on'
temp=root/'preferences/new';temp.write_text(json.dumps(dict(schema=1,uid=1000,hardware=hardware)));os.replace(temp,path)
lease=root/'performance/hardware-1000.json'
if enabled and hardware:lease.write_text('{"schema":1}')
else:lease.unlink(missing_ok=True)
active=enabled and len(calls.read_text().splitlines())>=4
value={'timestamp':time.time(),'native':{'focus_performance':dict(schema=1,uid=1000,available=True,enabled=enabled,active=active,reason='focused-cpu-boost' if active else 'no-isolated-focused-workload' if enabled else 'off')}}
temp=root/'run/new';temp.write_text(json.dumps(value));os.replace(temp,root/'run/status.json')
''')
    helper.chmod(0o755)
    (root / 'shell/shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property int step: 0
 Component.onCompleted: {
  FocusMode.runtimePath = RUNTIME; FocusMode.executable = HELPER;
  FocusMode.performancePath = PERFORMANCE; FocusMode.preferencesPath = PREFERENCES;
 }
 Timer {
  interval: 150; repeat: true; running: true
  onTriggered: {
   step++;
   if (step === 3) FocusMode.setEnabled(true);
   if (step === 8) {
    if (!FocusMode.enabled || FocusMode.active || FocusMode.busy || FocusMode.statusText !== "On · app not eligible") { console.log("FAIL eligibility status"); Qt.quit(); return; }
    FocusMode.setHardwareEnabled(true);
   }
   if (step === 13) {
    if (!FocusMode.hardwareEnabled || !FocusMode.hardwareLeased) { console.log("FAIL hardware choice"); Qt.quit(); return; }
    FocusMode.setEnabled(false);
   }
   if (step === 18) {
    if (FocusMode.enabled || FocusMode.active || FocusMode.hardwareLeased || !FocusMode.hardwareEnabled || FocusMode.statusText !== "Off") { console.log("FAIL master off and saved preference"); Qt.quit(); return; }
    FocusMode.setEnabled(true);
   }
   if (step === 23) {
    if (!FocusMode.enabled || !FocusMode.active || !FocusMode.hardwareLeased || FocusMode.statusText !== "CPU priority active") { console.log("FAIL resumed choice"); Qt.quit(); return; }
    FocusMode.setHardwareEnabled(false);
   }
   if (step === 28) {
    if (!FocusMode.enabled || FocusMode.hardwareEnabled || FocusMode.hardwareLeased) { console.log("FAIL hardware off"); Qt.quit(); return; }
    FocusMode.setEnabled(false);
   }
   if (step === 33) FocusMode.setEnabled(true);
   if (step === 38) {
    if (FocusMode.enabled || !FocusMode.error.includes("fixture refusal")) { console.log("FAIL refusal"); Qt.quit(); return; }
    console.log("FOCUS_QML_PASS");Qt.quit();
   }
  }
 }
}
'''.replace('RUNTIME', json.dumps(str(root / 'run'))).replace('HELPER', json.dumps(str(helper)))
   .replace('PERFORMANCE', json.dumps(str(root / 'performance'))).replace('PREFERENCES', json.dumps(str(root / 'preferences'))))
    env = dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'home/config'),
               XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'),
               QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', WAYLAND_DISPLAY='')
    for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
        env.pop(key, None)
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root / 'shell')],
                            env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and 'FOCUS_QML_PASS' in output and 'FAIL ' not in output, output
    assert (root / 'calls').read_text().splitlines() == ['on', 'hardware-on', 'off', 'on', 'hardware-off', 'off', 'on']
    print('PASS: private QML master, eligibility versus applied priority, hardware choice and retirement, surfaced refusal; no polling subprocesses')
