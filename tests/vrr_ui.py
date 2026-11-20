#!/usr/bin/env python3
"""Exercise the real VRR panel with an inert service and an isolated Qt scene."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
artifact = Path('/tmp/vrr-panel-preview.png')
with tempfile.TemporaryDirectory(prefix='vrr-ui-') as tmp:
    root = Path(tmp)
    imports = root / 'imports'
    modules = {
        'qs/services': 'singleton Vrr 1.0 Vrr.qml\n',
        'qs/modules/common': 'singleton Appearance 1.0 Appearance.qml\n',
        'qs/modules/common/widgets': 'StyledText 1.0 StyledText.qml\nStyledComboBox 1.0 StyledComboBox.qml\nMaterialSymbol 1.0 MaterialSymbol.qml\n',
    }
    for name, entries in modules.items():
        directory = imports / name
        directory.mkdir(parents=True)
        (directory / 'qmldir').write_text('module ' + name.replace('/', '.') + '\n' + entries)
    (imports / 'qs/services/Vrr.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool ready: true
 property bool busy: false
 property int globalPolicy: 2
 property int watchers: 0
 property string error: ""
 property string lastOutput: ""
 property int lastPolicy: -99
 property var modes: [{value:0,label:"0 · Off"},{value:1,label:"1 · Always"},{value:2,label:"2 · Fullscreen only"},{value:3,label:"3 · Fullscreen games & video"}]
 property var monitors: [{name:"DP-1",label:"AOC 27G2G4 · DP-1",policy:-1,effective:2,gpu:false,active:false,focused:true,width:1920,height:1080,hz:60,mismatch:false},
 {name:"HDMI-A-1",label:"GWD ARZOPA · HDMI-A-1",policy:0,effective:0,gpu:false,active:false,focused:false,width:1920,height:1080,hz:60,mismatch:false}]
 function setPolicy(output,policy) { lastOutput=output;lastPolicy=policy; }
}
''')
    (imports / 'qs/modules/common/Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property var m3colors: ({m3primary:"#cbb5ff",m3error:"#ff9999",m3onSurfaceVariant:"#c9c3d2"}) }
''')
    widgets = imports / 'qs/modules/common/widgets'
    (widgets / 'StyledText.qml').write_text('import QtQuick\nText { color:"#f5efff" }\n')
    (widgets / 'MaterialSymbol.qml').write_text('import QtQuick\nText { property int iconSize:23; font.pixelSize:iconSize }\n')
    (widgets / 'StyledComboBox.qml').write_text('import QtQuick.Controls\nComboBox { implicitHeight:40 }\n')
    shutil.copy2(repo / 'dots/.config/quickshell/ii/modules/ii/sidebarRight/quickToggles/VrrPanel.qml', root / 'VrrPanel.qml')
    scene = '''import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtTest
import qs.services
Rectangle {
 id:scene; width:560;height:290;color:"#211c2b"
 VrrPanel { id:panel; x:18;y:18;width:524;height:250 }
 TestCase {
  name:"VrrPanel";when:windowShown
  function init() { panel.selectedOutput="DP-1";Vrr.ready=true;Vrr.busy=false;Vrr.error="";Vrr.lastPolicy=-99; }
  function test_defaults_to_focused_monitor_and_inherit() {
   compare(panel.selectedOutput,"DP-1");compare(panel.policy,-1);
   compare(findChild(panel,"vrrModePicker").count,5);
   compare(findChild(panel,"vrrModePicker").currentIndex,0);
  }
  function test_all_monitor_modes_and_inherit_route_to_selected_output() {
   let mode=findChild(panel,"vrrModePicker");
   for(let i=0;i<5;i++) { mode.activated(i);compare(Vrr.lastOutput,"DP-1");compare(Vrr.lastPolicy,i-1); }
   findChild(panel,"vrrMonitorPicker").activated(2);
   mode.activated(3);compare(Vrr.lastOutput,"HDMI-A-1");compare(Vrr.lastPolicy,2);
  }
  function test_global_has_four_modes() {
   findChild(panel,"vrrMonitorPicker").activated(0);
   compare(panel.selectedOutput,"global");compare(findChild(panel,"vrrModePicker").count,4);
   findChild(panel,"vrrModePicker").activated(2);compare(Vrr.lastOutput,"global");compare(Vrr.lastPolicy,2);
  }
  function test_busy_disables_changes_and_error_visible() {
   Vrr.busy=true;verify(!findChild(panel,"vrrModePicker").enabled);
   Vrr.error="Display disconnected";compare(findChild(panel,"vrrActualState").text,"Display disconnected");
  }
  function test_narrow_layout_fits_and_tracks_visibility() {
   panel.width=290;wait(20);
   for(let name of ["vrrMonitorPicker","vrrModePicker"]) {
    let node=findChild(panel,name);let p=node.mapToItem(panel,0,0);
    verify(p.x>=0);verify(p.x+node.width<=panel.width+1);
   }
   verify(Vrr.watchers>0);panel.visible=false;compare(Vrr.watchers,0);panel.visible=true;verify(Vrr.watchers>0);
   panel.width=524;
  }
  function test_hidden_window_stops_polling() {
   let win=scene.Window.window;verify(win!==null);
   win.visible=false;compare(Vrr.watchers,0);
   win.visible=true;verify(Vrr.watchers>0);
  }
  function cleanupTestCase() {
   panel.selectedOutput="DP-1";Vrr.busy=false;Vrr.error="";wait(30);
   let saved=false;scene.grabToImage(result=>{saved=result.saveToFile(ARTIFACT);});
   tryVerify(()=>saved,3000);
  }
 }
}
'''.replace('ARTIFACT', json.dumps(str(artifact)))
    (root / 'tst_vrr.qml').write_text(scene)
    (root / 'runtime').mkdir(mode=0o700)
    env = dict(os.environ, HOME=str(root), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QT_QUICK_CONTROLS_STYLE='Basic', XDG_RUNTIME_DIR=str(root / 'runtime'),
               XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'))
    result = subprocess.run(['dbus-run-session', '--', '/usr/lib/qt6/bin/qmltestrunner',
                             '-input', str(root), '-import', str(imports)],
                            env=env, capture_output=True, text=True, timeout=30)
    print(result.stdout)
    if result.returncode:
        print(result.stderr)
    result.check_returncode()
