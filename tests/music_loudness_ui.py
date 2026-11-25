#!/usr/bin/env python3
"""Test the real loudness card and settings with an isolated, inert service."""
from pathlib import Path
import os,shutil,subprocess,tempfile
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='music-loudness-ui-') as tmp:
 root=Path(tmp);imports=root/'imports'
 for name,qmldir in {'Quickshell':'module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n','qs/services':'module qs.services\nsingleton MusicLoudness 1.0 MusicLoudness.qml\n',
  'qs/modules/common':'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n',
  'qs/modules/common/widgets':'module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\nMaterialSymbol 1.0 MaterialSymbol.qml\n'}.items():
  d=imports/name;d.mkdir(parents=True);(d/'qmldir').write_text(qmldir)
 (imports/'Quickshell/Quickshell.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var screens: [] }\n')
 (imports/'qs/services/MusicLoudness.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool enabled: true
 property var apps: [{id:"exe:mpv",name:"mpv"},{id:"exe:firefox",name:"Firefox"}]
 property string selectedApp: "exe:mpv"
 property bool matchReady: true
 property string matchMessage: "Measure selected app"
 property bool ready: true
 property bool active: false
 property bool busy: false
 property bool measuring: false
 property bool followPresets: true
 property bool edenDefault: false
 function setEdenDefault(v) { edenDefault=v; }
 property bool autoMatch: false
 property real autoInterval: 30
 property string autoMessage: ""
 property real db: 0
 property real stepDb: 1
 property real targetLufs: -16
 property string title: "Donna Summer — Bad Girls (Dolby Atmos)"
 property string message: "Limiter ready · EQ unchanged"
 property string error: ""
 property string lastAction: ""
 function refresh() {}
 function selectApp(value) { selectedApp=value;lastAction="select:"+value;db=0;active=false; }
 function adjust(n) { lastAction="adjust:"+n;db+=n*stepDb;active=db!==0; }
 function match() { lastAction="match";measuring=true;busy=true; }
 function reset() { lastAction="reset";db=0;active=false;measuring=false;busy=false; }
 function setEnabled(v) { enabled=v;lastAction=v?"enable":"disable"; }
 function setTarget(v) { targetLufs=v;lastAction="target"; }
 function setFollowPresets(v) { followPresets=v; }
 function setStep(v) { stepDb=v; }
 function setAutoMatch(v) { autoMatch=v;lastAction=v?"auto-on":"auto-off"; }
 function setAutoInterval(v) { autoInterval=v; }
}
''')
 (imports/'qs/modules/common/Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property var m3colors: ({m3error:"#ff9999",m3onSurface:"white",m3onSurfaceVariant:"#cccccc",m3primary:"#8ab4f8",m3secondaryContainer:"#24413a",m3surfaceContainerLow:"#25292e",m3surfaceContainerHigh:"#25292e",m3surfaceContainerHighest:"#34383d",m3outline:"white",m3outlineVariant:"gray",m3onPrimary:"white"}) }
''')
 (imports/'qs/modules/common/widgets/MaterialSymbol.qml').write_text('import QtQuick\nItem { property int iconSize: 18; property string text; property color color; implicitWidth: iconSize; implicitHeight: iconSize; Text { anchors.centerIn: parent; text: "⌄"; color: parent.color; font.pixelSize: parent.iconSize } }\n')
 (imports/'qs/modules/common/widgets/StyledText.qml').write_text('import QtQuick\nText { color: "white" }\n')
 src=repo/'dots/.config/quickshell/ii/modules'
 shutil.copy2(src/'ii/sidebarRight/MusicLoudnessWidget.qml',root/'MusicLoudnessWidget.qml')
 for name in ['MusicLoudnessControls.qml','SettingsSwitch.qml','SettingsButton.qml','SettingsComboBox.qml','SettingsCheckBox.qml','TimingSettingRow.qml','SettingRow.qml','SettingsField.qml','SettingsCatalog.js']:shutil.copy2(src/'settings'/name,root/name)
 for name,body in [('Config','property bool ready: true'),('Translation','function tr(value) { return value; }')]:
  directory=imports/('qs/modules/common' if name=='Config' else 'qs/services')
  with (directory/'qmldir').open('a') as manifest:manifest.write(f'singleton {name} 1.0 {name}.qml\n')
  (directory/(name+'.qml')).write_text('pragma Singleton\nimport QtQuick\nQtObject { '+body+' }\n')
 (root/'QuickTileEditor.qml').write_text('import QtQuick\nItem { property var tiles; signal edited(var value) }\n')
 (root/'tst_loudness.qml').write_text('''import QtQuick
import QtTest
import qs.services
Rectangle {
 id:scene;width:900;height:850;color:"#15191e"
 MusicLoudnessWidget { id:card;width:340 }
 MusicLoudnessControls { id:settings;x:390;width:480 }
 TestCase {
  name:"MusicLoudnessCard";when:windowShown
  function init() { MusicLoudness.enabled=true;MusicLoudness.ready=true;MusicLoudness.matchReady=true;MusicLoudness.busy=false;MusicLoudness.measuring=false;MusicLoudness.db=0;MusicLoudness.active=false;MusicLoudness.error="";MusicLoudness.autoMatch=false;MusicLoudness.autoInterval=30; }
  function test_auto_checkbox_and_interval_are_shared() {
   let box=findChild(card,"musicLoudnessAutoMatch"),setting=findChild(settings,"musicLoudnessSettingsAutoMatch"),interval=findChild(settings,"choice:musicLoudness.autoInterval");
   verify(box!==null&&setting!==null&&interval!==null);verify(!box.checked);verify(!interval.visible);
   mouseClick(box);compare(MusicLoudness.lastAction,"auto-on");verify(setting.checked);verify(interval.visible);compare(interval.currentText,"30 seconds");
   interval.activated(2);compare(MusicLoudness.autoInterval,60);
   mouseClick(setting);compare(MusicLoudness.lastAction,"auto-off");verify(!box.checked);
  }
  function test_eden_default_toggle() {
   let box=findChild(settings,"musicLoudnessEdenDefault");verify(box!==null);
   mouseClick(box);verify(MusicLoudness.edenDefault);
   mouseClick(box);verify(!MusicLoudness.edenDefault);
  }
  function test_picker_selects_firefox() {
   let picker=findChild(card,"musicLoudnessApp");verify(picker!==null);
   compare(picker.count,2);picker.activated(1);
   compare(MusicLoudness.selectedApp,"exe:firefox");compare(MusicLoudness.lastAction,"select:exe:firefox");
   compare(findChild(settings,"musicLoudnessSettingsApp").currentText,"Firefox");
   MusicLoudness.selectedApp="exe:mpv";
  }
  function test_mixed_audio_keeps_manual_gain_available() {
   MusicLoudness.matchReady=false;
   verify(findChild(card,"musicLoudnessPlus").enabled);verify(!findChild(card,"musicLoudnessMatch").enabled);
  }
  function test_steps_and_middle_info() {
   let minus=findChild(card,"musicLoudnessMinus"),plus=findChild(card,"musicLoudnessPlus"),value=findChild(card,"musicLoudnessValue");
   verify(minus!==null&&plus!==null&&value!==null);
   mouseClick(plus);compare(MusicLoudness.lastAction,"adjust:1");compare(value.text,"+1.0 dB");
   mouseClick(minus);compare(MusicLoudness.lastAction,"adjust:-1");compare(value.text,"0.0 dB");
   verify(minus.mapToItem(card,0,0).x < value.mapToItem(card,0,0).x);
   verify(value.mapToItem(card,0,0).x < plus.mapToItem(card,0,0).x);
   verify(plus.mapToItem(card,0,0).x+plus.width<=card.width);
  }
  function test_measurement_can_be_cancelled_and_steps_are_disabled() {
   let match=findChild(card,"musicLoudnessMatch"),reset=findChild(card,"musicLoudnessReset"),plus=findChild(card,"musicLoudnessPlus");
   mouseClick(match);compare(MusicLoudness.lastAction,"match");verify(!plus.enabled);verify(!match.enabled);verify(reset.enabled);
   mouseClick(reset);compare(MusicLoudness.lastAction,"reset");verify(!MusicLoudness.measuring);compare(MusicLoudness.db,0);
  }
  function test_missing_audio_disables_gain_without_hiding_status() {
   MusicLoudness.ready=false;MusicLoudness.message="Play music first";
   verify(!findChild(card,"musicLoudnessPlus").enabled);verify(!findChild(card,"musicLoudnessMinus").enabled);
   compare(findChild(card,"musicLoudnessStatus").text,"Play music first");
  }
  function test_master_and_hidden_controls() {
   let master=findChild(settings,"musicLoudnessMaster"),features=findChild(settings,"musicLoudnessSettings");
   mouseClick(master);compare(MusicLoudness.lastAction,"disable");verify(!features.visible);verify(!card.visible);
   mouseClick(master);compare(MusicLoudness.lastAction,"enable");verify(features.visible);verify(card.visible);
  }
  function test_settings_show_the_actual_step_and_target() {
   let step=findChild(settings,"musicLoudnessStep"),target=findChild(settings,"musicLoudnessTarget");
   compare(step.currentText,"1 dB");compare(target.text,"-16");
   MusicLoudness.stepDb=0.5;compare(step.currentText,"0.5 dB");
   MusicLoudness.stepDb=1;
  }
  function test_narrow_card_and_long_metadata() {
   card.width=280;MusicLoudness.title="A very long song title — 日本語の音楽 — with several edition names";wait(50);
   let plus=findChild(card,"musicLoudnessPlus"),title=findChild(card,"musicLoudnessTrack");
   verify(title.width>0);verify(plus.mapToItem(card,0,0).x+plus.width<=card.width);
   verify(card.implicitHeight>100);card.width=340;
  }
 }
}
''')
 artifact=os.environ.get('MUSIC_LOUDNESS_UI_ARTIFACT')
 if artifact:
  import json
  fixture=root/'tst_loudness.qml'
  source=fixture.read_text().replace('function init() {','''function cleanupTestCase() {
   MusicLoudness.enabled=true;MusicLoudness.ready=true;MusicLoudness.db=2;MusicLoudness.active=true;
   MusicLoudness.title="Donna Summer — Bad Girls";MusicLoudness.message="Limiter active · EQ unchanged";
   card.width=340;wait(100);
   let saved=false;scene.grabToImage(function(result) { saved=result.saveToFile(ARTIFACT); });
   tryVerify(function() { return saved; },3000);
  }
  function init() {'''.replace('ARTIFACT',json.dumps(artifact)))
  fixture.write_text(source)
 (root/'runtime').mkdir(mode=0o700)
 env=dict(os.environ,HOME=str(root),QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic',XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'),XDG_RUNTIME_DIR=str(root/'runtime'),PIPEWIRE_REMOTE='music-loudness-no-audio-server')
 result=subprocess.run(['dbus-run-session','--','/usr/lib/qt6/bin/qmltestrunner','-input',str(root),'-import',str(imports),'-o',str(root/'results.txt')+',txt'],env=env,capture_output=True,text=True,timeout=30)
 report=(root/'results.txt').read_text() if (root/'results.txt').exists() else result.stderr
 print(report)
 if result.returncode:print(result.stderr)
 result.check_returncode()
 assert 'TypeError' not in report and 'ReferenceError' not in report
