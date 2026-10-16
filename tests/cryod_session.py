#!/usr/bin/env python3
"""Real QML service + native bridge + private observer; synthetic window hints."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
native = Path(sys.argv[1]).resolve()
source = repo.parent/'cryoManager/native/desktop'
with tempfile.TemporaryDirectory(prefix='cryod-qml-session-') as directory:
    root = Path(directory)
    shell = root/'shell'
    for name in ('services', 'modules/common'):
        (shell/name).mkdir(parents=True)
    for name in ('runtime', 'cache', 'home'):
        (root/name).mkdir(mode=0o700)
    shutil.copy2(repo/'dots/.config/quickshell/ii/services/CryoDSession.qml', shell/'services/CryoDSession.qml')
    (shell/'modules/common/Config.qml').write_text('''pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
 property bool ready: true
 signal reloaded()
 property JsonObject options: JsonObject { property JsonObject cryod: JsonObject {
  property bool enabled: false
  property bool protectForeground: true
  property bool protectVisible: true
 } }
}
''')
    (shell/'services/HyprlandData.qml').write_text('''pragma Singleton
import Quickshell
Singleton {
 property var windowList: []
 property var monitors: []
 property var workspaces: []
}
''')
    window = subprocess.Popen(['/usr/bin/sleep', '60'])
    daemon = subprocess.Popen([str(native), '--observe', '--config', str(source/'native.conf'),
        '--guard', str(source/'desktop_guard.py'), '--runtime-dir', str(root/'native-run'),
        '--state-dir', str(root/'native-state')], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic()+8
        while not (root/'native-run/session.sock').is_socket():
            assert time.monotonic() < deadline and daemon.poll() is None
            time.sleep(.02)
        (shell/'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
import qs.modules.common
ShellRoot {
 property int step: 0
 property int producer: 0
 function fail(message) { console.log("CRYOD_QML_FAIL " + message); Qt.quit(); }
 Component.onCompleted: {
  CryoDSession.runtimePath = RUNTIME;
  CryoDSession.bridgeExecutable = BRIDGE;
  HyprlandData.windowList = [{pid: PID, address:"0x1", workspace:{id:1}, monitor:0, mapped:true, hidden:false}];
  HyprlandData.monitors = [{id:0, activeWorkspace:{id:1}}];
  CryoDSession.start();
 }
 Timer {
  interval: 150; running: true; repeat: true
  onTriggered: {
   step++;
   if (step === 4) Config.options.cryod.enabled = true;
   if (step === 10) {
    if (!CryoDSession.fresh) { fail("not fresh " + JSON.stringify(CryoDSession.receipt)); return; }
    producer = CryoDSession.receipt.producer_pid;
   }
   if (step >= 11 && step <= 24) HyprlandData.monitors = [{id:0, activeWorkspace:{id:step % 2 + 1}}];
   if (step === 27) {
    if (!CryoDSession.fresh || CryoDSession.receipt.producer_pid !== producer) { fail("producer duplicated or stale"); return; }
    Config.options.cryod.enabled = false;
   }
   if (step === 33) {
    if (CryoDSession.receipt.enabled !== false) { fail("off not acknowledged"); return; }
    console.log("CRYOD_QML_PASS " + producer + " sequence=" + CryoDSession.receipt.sequence);
    Qt.quit();
   }
  }
 }
}
'''.replace('RUNTIME', json.dumps(str(root/'native-run'))).replace('BRIDGE', json.dumps(str(native.with_name('cryod-session-bridge')))).replace('PID', str(window.pid)))
        env = dict(os.environ, HOME=str(root/'home'), XDG_CONFIG_HOME=str(root/'home/config'),
                   XDG_CACHE_HOME=str(root/'cache'), XDG_RUNTIME_DIR=str(root/'runtime'),
                   QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   HYPRLAND_INSTANCE_SIGNATURE='fixture_session', WAYLAND_DISPLAY='')
        for name in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):
            env.pop(name, None)
        result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(shell)],
                                env=env, capture_output=True, text=True, timeout=12)
        output = result.stdout+result.stderr
        assert result.returncode == 0 and 'CRYOD_QML_PASS ' in output and 'CRYOD_QML_FAIL ' not in output, output[-16000:]
        mode = json.loads((root/'native-state/focus-mode.json').read_text())
        assert not mode['enabled']
        receipt = json.loads((root/'native-run/focus.json').read_text())
        deadline = time.monotonic()+2
        while receipt['producer_pid'] and time.monotonic()<deadline:
            time.sleep(.02);receipt=json.loads((root/'native-run/focus.json').read_text())
        assert receipt['producer_pid'] == 0, receipt
        print('PASS: QML events use one persistent native bridge; master Off acknowledged and bridge exited')
    finally:
        daemon.terminate();daemon.wait(timeout=15)
        window.terminate();window.wait(timeout=3)
