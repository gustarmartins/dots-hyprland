"""Exercise the fullscreen scanout switch with a private shell and a simulated compositor."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1] / 'dots/.config/quickshell/ii'
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    shell = root / 'shell'
    for name in ('modules/common/models/quickToggles/DirectScanoutToggle.qml',
                 'modules/common/models/quickToggles/QuickToggleModel.qml',
                 'modules/common/models/hyprland/HyprlandConfigOption.qml',
                 'modules/common/models/NestableObject.qml'):
        dest = shell / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, dest)
    services = shell / 'services'
    services.mkdir()
    (services / 'Translation.qml').write_text('pragma Singleton\nimport QtQml\nQtObject { function tr(s) { return s } }\n')
    (services / 'HyprlandConfig.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    signal reloaded()
    property string lastKey
    property int lastValue: -1
    function set(key, value) {
        lastKey = key
        lastValue = value
        write.command = ["fake-write", key, String(value)]
        write.running = true
    }
    Process { id: write; onExited: (code, status) => { if (code === 0) reloaded() } }
}
''')
    (shell/'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
import qs.modules.common.models.quickToggles
ShellRoot {
    DirectScanoutToggle { id: tile }
    Timer {
        property int step: 0
        interval: 30; running: true; repeat: true
        onTriggered: {
            if (!tile.available) return
            if (step === 0 && tile.toggled) { tile.mainAction(); step++ }
            else if (step === 1 && !tile.toggled && HyprlandConfig.lastValue === 0) {
                tile.mainAction(); step++
            } else if (step === 2 && tile.toggled && HyprlandConfig.lastValue === 1
                       && HyprlandConfig.lastKey === "render:direct_scanout") {
                console.log("SCANOUT_POLICY_OK"); Qt.quit()
            }
        }
    }
}
''')
    state = root/'state'
    state.write_text('2\n')
    for name,script in {
        'hyprctl':'test "$1 $2 $3" = "getoption -j render:direct_scanout" || exit 1\nprintf \'{"option":"render:direct_scanout","int":%s,"set":true}\\n\' "$(cat "$TEST_STATE")"',
        'fake-write':'test "$1" = render:direct_scanout || exit 1\nprintf "%s\\n" "$2" >"$TEST_STATE"',
    }.items():
        file=root/name
        file.write_text('#!/bin/sh\n'+script+'\n')
        file.chmod(0o755)
    runtime=root/'run';runtime.mkdir(mode=0o700)
    env=dict(PATH=str(root)+':/usr/bin',HOME=tmp,XDG_RUNTIME_DIR=str(runtime),QT_QPA_PLATFORM='offscreen',
             XDG_CONFIG_HOME=str(root/'config'),XDG_DATA_HOME=str(root/'data'),XDG_CACHE_HOME=str(root/'cache'),
             TEST_STATE=str(state),NO_AT_BRIDGE='1')
    run=subprocess.run(['dbus-run-session','--','/usr/bin/qs','-p',str(shell/'shell.qml')],
                       env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=12)
    assert run.returncode==0 and 'SCANOUT_POLICY_OK' in run.stdout and state.read_text().strip()=='1',run.stdout[-2200:]
    print('Verified old automatic selection, Off, On for fullscreen, and compositor readback.')
