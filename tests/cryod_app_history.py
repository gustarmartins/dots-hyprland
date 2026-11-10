#!/usr/bin/env python3
"""Actual consent singleton: suggestion replies, persistence, read-only reload and Off."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cryod-app-history-') as directory:
    root = Path(directory)
    for part in ('services', 'modules/common', 'state', 'runtime'):
        (root/part).mkdir(mode=0o700, parents=True)
    for name in ('CryoDConsent.qml', 'CryoDAppStats.js', 'CryoDAppLaunch.qml'):
        shutil.copy2(repo/'dots/.config/quickshell/ii/services'/name, root/'services'/name)
    (root/'services/Notifications.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { signal notify(wrapper: var) }\n')
    (root/'modules/common/Config.qml').write_text('''pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
 property bool ready: true
 property JsonObject options: JsonObject { property JsonObject cryod: JsonObject {
  property bool enabled: true
  property bool freezeSuggestions: false
  property bool groupLaunches: false
 } }
}
''')
    history = root/'state/history.json'
    (root/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted: {
  CryoDConsent.historyPath = HISTORY;
  CryoDConsent.historySaveInterval = 25;
 }
 IpcHandler {
  target: "test"
  function state(): string { return JSON.stringify({ready:CryoDConsent.historyReady,
   history:CryoDConsent.history,error:CryoDConsent.historyError}); }
  function owner(value: bool): void { CryoDConsent.owner = value; }
  function enabled(value: bool): void { Config.options.cryod.enabled = value; }
  function sample(): void {
   CryoDConsent.pending = {purpose:"suggest-poll",generation:CryoDConsent.generation,context:{automatic:true,cursor:0}};
   CryoDConsent.responseText = JSON.stringify({scope:"application-consent",ok:true,interval_ms:10000,next_cursor:0,
    apps:[{app_id:"observed.desktop",pid:42,start_ticks:"100",cpu_percent_x100:"1250",recommended:false}]});
   CryoDConsent.resultCode = 0;
   CryoDConsent.finish();
  }
 }
}
'''.replace('HISTORY',json.dumps(str(history))))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=str(root/'runtime'),
               XDG_STATE_HOME=str(root/'state'), HOME=str(root))
    env.pop('WAYLAND_DISPLAY',None)
    log=(root/'qml.log').open('w+')
    def call(*args):
        return subprocess.check_output(['qs','-p',str(root),'ipc','call','test',*args],env=env,text=True,stderr=subprocess.DEVNULL,timeout=3).strip()
    def wait(fn):
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            try:
                value=fn()
                if value:return value
            except (subprocess.SubprocessError,ValueError,FileNotFoundError):pass
            time.sleep(.05)
        log.flush();raise AssertionError((root/'qml.log').read_text())
    process=subprocess.Popen(['qs','-p',str(root)],env=env,stdout=log,stderr=log)
    try:
        wait(lambda:json.loads(call('state'))['ready'])
        call('sample')
        time.sleep(.1)
        assert not history.exists(), 'settings reader wrote observations'
        call('owner','true');call('sample')
        wait(lambda:history.exists())
        saved=json.loads(history.read_text())
        assert saved['apps'][0]['cpu_peak_x100']==1250
        call('enabled','false');call('sample')
        time.sleep(.1)
        assert json.loads(history.read_text())==saved
        call('enabled','true');call('owner','false')
        wait(lambda:json.loads(call('state'))['ready'])
        saved['apps'][0]['cpu_peak_x100']=2600
        history.write_text(json.dumps(saved))
        wait(lambda:json.loads(call('state'))['history'][0]['cpu_peak_x100']==2600)
        history.write_text('{broken')
        wait(lambda:bool(json.loads(call('state'))['error']))
        call('owner','true');call('sample');time.sleep(.1)
        assert history.read_text()=='{broken', 'corrupt history overwritten'
        history.write_text(json.dumps(saved))
    finally:
        process.terminate();process.wait(timeout=5)
    process=subprocess.Popen(['qs','-p',str(root)],env=env,stdout=log,stderr=log)
    try:
        wait(lambda:json.loads(call('state'))['ready'])
        assert json.loads(call('state'))['history'][0]['cpu_peak_x100']==2600
        print('PASS: native-format CPU reply retained, sole writer, file watch, master Off, corrupt-file preservation and restart')
    finally:
        process.terminate();process.wait(timeout=5);log.close()
