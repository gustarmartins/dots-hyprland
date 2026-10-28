#!/usr/bin/env python3
"""Exercise the actual spatial controls offscreen with a fake service singleton."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='spatial-audio-ui-') as tmp:
    root=Path(tmp);imports=root/'imports'
    for name, qmldir in {
        'qs/services':'module qs.services\nsingleton SpatialAudio 1.0 SpatialAudio.qml\n',
        'qs/modules/common':'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n',
        'qs/modules/common/widgets':'module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\n',
    }.items():
        p=imports/name;p.mkdir(parents=True);(p/'qmldir').write_text(qmldir)
    (imports/'qs/services/SpatialAudio.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool enabled: false
 property bool automatic: true
 property bool busy: false
 property string message: "Off"
 property string error: ""
 property string lastAction: ""
 function refresh() {}
 function setEnabled(value) { enabled=value;lastAction=value?"enable":"disable"; }
 function setAutomatic(value) { automatic=value;lastAction=value?"automatic-on":"automatic-off"; }
}
''')
    (imports/'qs/modules/common/Appearance.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var m3colors: ({m3error:"red",m3onSurfaceVariant:"white",m3primary:"blue",m3surfaceContainerHighest:"gray",m3outline:"white",m3onPrimary:"white"}) }\n')
    (imports/'qs/modules/common/widgets/StyledText.qml').write_text('import QtQuick\nText {}\n')
    source=repo/'dots/.config/quickshell/ii/modules/settings'
    for name in ['SpatialAudioControls.qml','SettingsSwitch.qml']:shutil.copy2(source/name,root/name)
    (root/'SettingsButton.qml').write_text('import QtQuick.Controls\nButton {}\n')
    (root/'tst_spatial.qml').write_text('''import QtQuick
import QtTest
import qs.services
Item {
 width:800;height:500
 SpatialAudioControls { id:controls;width:760 }
 TestCase {
  name:"SpatialAudioSettings";when:windowShown
  function test_switches() {
   let master=findChild(controls,"mpvSpatialMaster");
   let features=findChild(controls,"mpvSpatialFeatures");
   let automatic=findChild(controls,"mpvSpatialAutomatic");
   verify(master!==null);verify(features!==null);verify(automatic!==null);
   verify(!features.visible);verify(!master.checked);
   mouseClick(master);compare(SpatialAudio.lastAction,"enable");verify(features.visible);
   mouseClick(automatic);compare(SpatialAudio.lastAction,"automatic-off");
   SpatialAudio.busy=true;verify(!master.enabled);verify(!automatic.enabled);
   SpatialAudio.busy=false;mouseClick(master);compare(SpatialAudio.lastAction,"disable");verify(!features.visible);
  }
 }
}
''')
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'))
    result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(root),'-import',str(imports),'-o',str(root/'results.txt')+',txt'],env=env,capture_output=True,text=True,timeout=25)
    report=(root/'results.txt').read_text() if (root/'results.txt').exists() else result.stderr
    print(report)
    if result.returncode:print(result.stderr)
    result.check_returncode()
    assert 'TypeError' not in report and 'ReferenceError' not in report
