#!/usr/bin/env python3
"""Exercise the real Quickshell singleton against an inert CLI on a private bus."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='music-loudness-service-') as temporary:
    root=Path(temporary)
    for name in ('shell/services','.local/bin','.config/music-loudness','runtime'):
        (root/name).mkdir(parents=True,mode=0o700)
    shutil.copy2(REPO/'dots/.config/quickshell/ii/services/MusicLoudness.qml',root/'shell/services/MusicLoudness.qml')
    (root/'shell/GlobalStates.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool sidebarRightOpen: true }\n')
    helper=root/'.local/bin/music-loudness'
    helper.write_text('''#!/usr/bin/env python3
import json,sys
from pathlib import Path
p=Path.home()/'.config/music-loudness/config.json'
s=json.loads(p.read_text()) if p.exists() else dict(enabled=True,ready=True,active=False,measuring=False,follow_presets=True,auto_match=False,auto_interval=30,db=0,step_db=1,target_lufs=-16,title='Test music',preset='Test preset',message='Ready',apps=[dict(id='exe:mpv',name='mpv'),dict(id='exe:firefox',name='Firefox')],selected_app='exe:mpv',match_ready=True,match_message='Only selected app')
a=sys.argv[1]
if a=='match':print('music-loudness: Test measurement refused',file=sys.stderr);sys.exit(1)
if a=='select-app':s['selected_app']=sys.argv[2];s['db']=0;s['active']=False
if a=='adjust':s['db']+=float(sys.argv[2]);s['active']=s['db']!=0
if a=='step':s['step_db']=float(sys.argv[2])
if a=='target':s['target_lufs']=float(sys.argv[2])
if a=='follow-presets':s['follow_presets']=sys.argv[2]=='true'
if a=='auto-match':s['auto_match']=sys.argv[2]=='true'
if a=='auto-interval':s['auto_interval']=float(sys.argv[2])
if a=='reset':s['db']=0;s['active']=False
if a in ('enable','disable'):s['enabled']=a=='enable';s['ready']=s['enabled']
if a!='status' or not p.exists():p.write_text(json.dumps(s))
print(json.dumps(s))
''')
    helper.chmod(0o700)
    (root/'shell/shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property int phase: 0
 property int ticks: 0
 Timer {
  interval:100;running:true;repeat:true
  onTriggered: {
   ticks++;
   if(ticks>150) { console.log("SERVICE_FAIL",phase,MusicLoudness.error);Qt.quit();return; }
   if(MusicLoudness.busy) return;
   if(phase===0 && MusicLoudness.enabled && MusicLoudness.ready) { MusicLoudness.setStep(0.5);phase++; }
   else if(phase===1 && MusicLoudness.stepDb===0.5) { MusicLoudness.adjust(1);phase++; }
   else if(phase===2 && MusicLoudness.db===0.5 && MusicLoudness.active) { MusicLoudness.setFollowPresets(false);phase++; }
   else if(phase===3 && !MusicLoudness.followPresets) { MusicLoudness.setTarget(-18);phase++; }
   else if(phase===4 && MusicLoudness.targetLufs===-18) { MusicLoudness.match();phase++; }
   else if(phase===5 && MusicLoudness.error==="Test measurement refused") { MusicLoudness.reset();phase++; }
   else if(phase===6 && MusicLoudness.db===0 && !MusicLoudness.active && MusicLoudness.error==="") { MusicLoudness.setEnabled(false);phase++; }
   else if(phase===7 && !MusicLoudness.enabled) { MusicLoudness.setEnabled(true);phase++; }
   else if(phase===8 && MusicLoudness.enabled) { MusicLoudness.selectApp("exe:firefox");phase++; }
   else if(phase===9 && MusicLoudness.selectedApp==="exe:firefox" && MusicLoudness.apps.length===2 && MusicLoudness.matchReady) { MusicLoudness.setAutoMatch(true);phase++; }
   else if(phase===10 && MusicLoudness.autoMatch && MusicLoudness.autoInterval===30) { MusicLoudness.setAutoInterval(60);phase++; }
   else if(phase===11 && MusicLoudness.autoInterval===60) { MusicLoudness.setAutoMatch(false);phase++; }
   else if(phase===12 && !MusicLoudness.autoMatch) { console.log("MUSIC_LOUDNESS_SERVICE_PASS");Qt.quit(); }
  }
 }
}
''')
    env=dict(os.environ,HOME=str(root),XDG_CONFIG_HOME=str(root/'.config'),XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'),XDG_DATA_HOME=str(root/'data'),XDG_RUNTIME_DIR=str(root/'runtime'),QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',PIPEWIRE_REMOTE='music-loudness-test-no-server')
    for key in ('WAYLAND_DISPLAY','HYPRLAND_INSTANCE_SIGNATURE','QS_CONFIG_PATH','QS_CONFIG_NAME'):
        env.pop(key,None)
    result=subprocess.run(['dbus-run-session','--','qs','-p',str(root/'shell'),'--no-color'],env=env,capture_output=True,text=True,timeout=25)
    output=result.stdout+result.stderr
    errors=('ERROR:','TypeError:','ReferenceError:','Binding loop','SERVICE_FAIL')
    assert result.returncode==0 and 'MUSIC_LOUDNESS_SERVICE_PASS' in output and not any(word in output for word in errors),output
    print('PASS: actual Quickshell service status, steps, target, preset option, error, reset and master off; isolated helper/home/bus')
