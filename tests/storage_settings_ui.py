#!/usr/bin/env python3
"""Exercise real storage controls offscreen, with process/notification IPC replaced."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='storage-ui-test-') as tmp:
    root = Path(tmp); imports = root / 'imports'
    modules = {
        'Quickshell': 'module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n',
        'Quickshell/Io': 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nsingleton Recorder 1.0 Recorder.qml\n',
        'qs/modules/common': 'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n',
        'qs/modules/common/widgets': 'module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\nSettingsButton 1.0 SettingsButton.qml\n',
    }
    for module, text in modules.items():
        p = imports / module; p.mkdir(parents=True); (p / 'qmldir').write_text(text)
    (imports / 'Quickshell/Quickshell.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function env(key) { return "/fixture"; } }\n')
    io = imports / 'Quickshell/Io'
    (io / 'Process.qml').write_text('''import QtQuick
QtObject {
 property var command: []
 property bool running: false
 property QtObject stdout
 property QtObject stderr
 signal exited(int code, int status)
 onRunningChanged: if (running) Recorder.lastCommand = command
}
''')
    (io / 'Recorder.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lastCommand: [] }\n')
    (io / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property string text: "" }\n')
    common = imports / 'qs/modules/common'
    (common / 'Appearance.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var m3colors: ({m3error:"red",m3onSurfaceVariant:"white"}) }\n')
    (common / 'widgets/StyledText.qml').write_text('import QtQuick\nText {}\n')
    (common / 'widgets/SettingsButton.qml').write_text('import QtQuick.Controls\nButton {}\n')
    shutil.copy2(repo / 'dots/.config/quickshell/ii/modules/settings/StorageActions.qml', root / 'StorageActions.qml')
    (root / 'tst_storage.qml').write_text('''import QtQuick
import QtTest
import Quickshell.Io
Item {
 width: 800; height: 900
 StorageActions { id: controls; width: 760 }
 TestCase {
  name: "StorageSettings"; when: windowShown
  function test_controls() {
   let master = findChild(controls, "storageMaster");
   let features = findChild(controls, "storageFeatures");
   verify(master !== null); verify(features !== null);
   controls.state = ({enabled:false, config:{}, disks:[]});
   verify(!features.visible);
   mouseClick(master);
   compare(Recorder.lastCommand[0], "/fixture/.local/bin/disk-reclaim");
   compare(Recorder.lastCommand[1], "enable");
   controls.state = ({enabled:true, timer_active:true, config:{nvme:true,ssd:true,hdd:true,desktop:true,forecast:true},
                      disks:[{name:"nvme",mounted:true,free:21474836480,level:"warning"}]});
   verify(features.visible);
   // The fake process does not exit automatically; release its busy state.
   for (let i=0; i<controls.data.length; i++) {
    let item=controls.data[i];
    if (item.command && item.command.length>1 && item.command[1]==="enable") item.running=false;
   }
   mouseClick(master);
   compare(Recorder.lastCommand[1], "disable");
   controls.state = ({enabled:false, config:{}, disks:[]});
   verify(!features.visible);
  }
 }
}
''')
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='software', QT_FORCE_STDERR_LOGGING='1')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root), '-import', str(imports),
                             '-o', str(root / 'results.txt') + ',txt'], env=env, capture_output=True, text=True, timeout=25)
    report = (root / 'results.txt').read_text() if (root / 'results.txt').exists() else result.stderr
    print(report)
    if result.returncode:
        print(result.stderr)
    result.check_returncode()
    assert 'TypeError' not in report and 'ReferenceError' not in report, report
