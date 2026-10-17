#!/usr/bin/env python3
"""Isolated mouse-gesture regression for the actual boost widget; no audio/desktop actions."""
from pathlib import Path
import os,shutil,subprocess,tempfile
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='eden-widget-test-') as tmp:
 root=Path(tmp);imports=root/'imports';services=imports/'qs/services';common=imports/'qs/modules/common';widgets=common/'widgets'
 for d in [services,common,widgets]:d.mkdir(parents=True,exist_ok=True)
 (services/'qmldir').write_text('module qs.services\nsingleton EdenAudioBoost 1.0 EdenAudioBoost.qml\n')
 (services/'EdenAudioBoost.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property bool enabled: true; property bool active: false; property bool busy: false; property int streams: 1; property string error: ""; property int boosts: 0; property int resets: 0; function boost() { boosts++; active=true; } function reset() { resets++; active=false; } }
''')
 (common/'qmldir').write_text('module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n')
 (common/'Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property var m3colors: ({m3errorContainer:"#550000",m3surfaceContainerHigh:"#222222",m3onErrorContainer:"white",m3onSurface:"white",m3onSurfaceVariant:"white"}) }
''')
 (widgets/'qmldir').write_text('module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\n')
 (widgets/'StyledText.qml').write_text('import QtQuick\nText {}\n')
 shutil.copy2(repo/'dots/.config/quickshell/ii/modules/ii/sidebarRight/EdenBoostWidget.qml',root/'EdenBoostWidget.qml')
 (root/'tst_boost.qml').write_text('''import QtQuick
import QtTest
import qs.services
Item {
 width: 500; height: 200
 EdenBoostWidget { id: widget; width: 480 }
 TestCase {
  name: "EdenDoubleClick"; when: windowShown
  function test_gestures() {
   mouseClick(widget,100,20); compare(EdenAudioBoost.boosts,0);
   wait(500);
   mouseDoubleClickSequence(widget,100,20); compare(EdenAudioBoost.boosts,1); verify(EdenAudioBoost.active);
   wait(500);
   mouseClick(widget,100,20); compare(EdenAudioBoost.resets,1); verify(!EdenAudioBoost.active);
   mouseDoubleClickSequence(widget,100,20); compare(EdenAudioBoost.boosts,1);
   wait(750);
   mouseDoubleClickSequence(widget,100,20); compare(EdenAudioBoost.boosts,2);
  }
 }
}
''')
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_FORCE_STDERR_LOGGING='1',QT_LOGGING_TO_CONSOLE='1')
 result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(root),'-import',str(imports),'-o',str(root/'result.txt')+',txt'],env=env,timeout=20)
 print((root/'result.txt').read_text() if (root/'result.txt').exists() else 'No Qt test report')
 result.check_returncode()
