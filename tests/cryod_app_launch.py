#!/usr/bin/env python3
"""Real DesktopEntry parsing, QML launch routing and native cgroup readback.

Only disposable scripts run. QML uses a private home/display/bus; its injected
test helper forwards scope creation to the owner's existing user manager.
"""
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
user_bus = os.environ.get('DBUS_SESSION_BUS_ADDRESS', f'unix:path=/run/user/{os.getuid()}/bus')
with tempfile.TemporaryDirectory(prefix='cryod-qml-launch-') as directory:
    root = Path(directory)
    for name in ('shell/services', 'shell/modules/common', 'home', 'data/applications', 'runtime', 'work space'):
        (root/name).mkdir(parents=True, mode=0o700)
    shutil.copy2(repo/'dots/.config/quickshell/ii/services/CryoDAppLaunch.qml', root/'shell/services')
    (root/'shell/modules/common/Config.qml').write_text('''pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
 property bool ready: true
 property JsonObject options: JsonObject { property JsonObject cryod: JsonObject {
  property bool enabled: false
  property bool groupLaunches: true
 } }
}
''')
    capture = root/'app.py'
    capture.write_text('''import json,os,subprocess,sys,time
from pathlib import Path
time.sleep(.4)
child=json.loads(subprocess.check_output([sys.executable,'-c',
 "import json,os;from pathlib import Path;print(json.dumps(dict(pid=os.getpid(),cgroup=Path('/proc/self/cgroup').read_text())))"]))
value=dict(pid=os.getpid(),cwd=os.getcwd(),args=sys.argv[2:],
 cgroup=Path('/proc/self/cgroup').read_text(),token=os.environ.get('CRYOD_TEST_TOKEN'),child=child)
with Path(sys.argv[1]).open('a') as f:f.write(json.dumps(value)+'\\n')
sys.exit(65)
''')
    helper = root/'helper'
    helper.write_text('#!/usr/bin/python3\nimport os,sys\n'
        +f'os.environ["DBUS_SESSION_BUS_ADDRESS"]={user_bus!r}\n'
        +f'os.execv({str(native)!r},[{str(native)!r},*sys.argv[1:]])\n')
    helper.chmod(0o755)
    app = root/'data/applications/com.mekki.launch-fixture.desktop'
    app.write_text(f'''[Desktop Entry]
Type=Application
Name=CryoD launch fixture
Exec=/usr/bin/python3 {capture} {root/'main.jsonl'} "literal $() ; apostrophe'" "" "üñïçødé"
Path={root/'work space'}
Terminal=false
Actions=Alternate;

[Desktop Action Alternate]
Name=Alternate
Exec=/usr/bin/python3 {capture} {root/'action.jsonl'} "alternate argument"
''')
    qml = '''import QtQuick
import Quickshell
import qs.services
import qs.modules.common
ShellRoot {
 property int tries: 0
 Timer { interval: 100; repeat: true; running: true; onTriggered: {
   const entry = DesktopEntries.byId("com.mekki.launch-fixture");
   if (!entry) { if (++tries < 50) return; console.error("FAIL: no fixture desktop entry"); Qt.quit(); return; }
   stop();
   if (CryoDAppLaunch.launch(entry)) throw new Error("master Off launched an app");
   Config.options.cryod.enabled = true;
   Config.options.cryod.groupLaunches = false;
   if (CryoDAppLaunch.launch(entry)) throw new Error("grouping Off launched an app");
   Config.options.cryod.groupLaunches = true;
   if (CryoDAppLaunch.launch({runInTerminal:true})) throw new Error("terminal launch taken over");
   CryoDAppLaunch.executable = HELPER;
   if (!CryoDAppLaunch.launch(entry)) throw new Error("main launch not routed");
   if (!CryoDAppLaunch.launch(entry, entry.actions[0])) throw new Error("action not routed");
   CryoDAppLaunch.executable = MISSING;
   if (!CryoDAppLaunch.launch(entry)) throw new Error("missing helper fallback not routed");
   console.log("CRYOD_LAUNCH_QML_PASS " + JSON.stringify({command:entry.command,action:entry.actions[0].command}));
   Qt.quit();
 } }
}
'''.replace('HELPER', json.dumps(str(helper))).replace('MISSING', json.dumps(str(root/'absent')))
    (root/'shell/shell.qml').write_text(qml)
    env = dict(os.environ, HOME=str(root/'home'), XDG_CONFIG_HOME=str(root/'home/.config'),
               XDG_CACHE_HOME=str(root/'home/.cache'), XDG_DATA_HOME=str(root/'data'),
               XDG_RUNTIME_DIR=str(root/'runtime'), QT_QPA_PLATFORM='offscreen',
               CRYOD_TEST_TOKEN='preserve application environment')
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root/'shell/shell.qml')],
                            env=env, capture_output=True, text=True, timeout=12)
    output = result.stdout+result.stderr
    assert 'CRYOD_LAUNCH_QML_PASS' in output, output
    parsed = json.loads(next(line.split('CRYOD_LAUNCH_QML_PASS ', 1)[1]
                             for line in output.splitlines() if 'CRYOD_LAUNCH_QML_PASS ' in line))
    deadline = time.monotonic()+5
    main, action = [], []
    while time.monotonic() < deadline:
        main = [json.loads(line) for line in (root/'main.jsonl').read_text().splitlines()] if (root/'main.jsonl').exists() else []
        action = [json.loads(line) for line in (root/'action.jsonl').read_text().splitlines()] if (root/'action.jsonl').exists() else []
        if len(main) >= 2 and action:
            break
        time.sleep(.05)
    assert len(main) == 2 and len(action) == 1, (output, main, action)
    assert sum('/app-cryod-' in item['cgroup'] for item in main) == 1, main
    assert '/app-cryod-' in action[0]['cgroup'], action
    # The app's exit 65 cannot cause a duplicate retry; descendants remain in
    # its scope, and quitting/reloading QML does not terminate the detached app.
    for item in main+action:
        assert item['cwd'] == str(root/'work space') and item['token'] == env['CRYOD_TEST_TOKEN'], item
        assert item['cgroup'] == item['child']['cgroup'], item
    assert main[0]['args'] == main[1]['args'] == parsed['command'][3:], main
    assert action[0]['args'] == parsed['action'][3:] == ['alternate argument'], action
    print('PASS: real desktop entry/action argv, cwd, environment and descendant scopes; detached apps survive QML exit')
    print('PASS: master/feature Off and terminal bypass; missing helper fallback once; app exit 65 never duplicates a launch')
