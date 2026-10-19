#!/usr/bin/env python3
"""Real QML, notification actions and native policy receipts on a private bus."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
base, build = (Path(path).resolve() for path in sys.argv[1:3])
source = repo.parent / 'cryoManager/native/desktop'


def wait(read, accept=bool):
    until = time.monotonic() + 12
    last = None
    while time.monotonic() < until:
        try:
            last = read()
            if accept(last):return last
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError):pass
        time.sleep(.05)
    raise AssertionError(('QML consent deadline', last))


with tempfile.TemporaryDirectory(prefix='cryod-qml-consent-') as temporary:
    root = Path(temporary)
    for name in ('shell/services', 'shell/modules/common', 'data/applications', 'home', 'cache', 'runtime'):
        (root / name).mkdir(parents=True, mode=0o700)
    config = root / 'native.conf';config.write_bytes((source / 'native.conf').read_bytes())
    account = root / 'runaway.conf';account.write_text((source / 'runaway.conf').read_text().replace('target_uid=1000', f'target_uid={os.getuid()}'))
    launcher = build / 'cryod-app-launch'
    env = dict(os.environ, XDG_DATA_HOME=str(root / 'data'), XDG_DATA_DIRS=str(root / 'no-system'),
               CRYOD_TEST_APPLICATION_LAUNCHER=str(launcher))
    policy = root / 'workload-policy.json'
    policy.write_bytes(subprocess.check_output([str(build / 'application-control-fixture'), '--workload-policy-template', str(account)], env=env))
    policy.chmod(0o600)
    entry = root / 'data/applications/com.mekki.qml-consent.desktop'
    entry.write_text(f'[Desktop Entry]\nType=Application\nName=Owned consent app\nExec=/usr/bin/sleep 120\nPath={root}\n')
    log = (root / 'native.log').open('w+')
    owner = subprocess.Popen([str(base / 'cryod-desktop'), '--observe', '--config', str(config),
        '--runtime-dir', str(root / 'native-run'), '--state-dir', str(root / 'state'),
        '--guard', str(source / 'desktop_guard.py'), '--control-worker', str(build / 'application-control-fixture')],
        env=env, stdout=subprocess.DEVNULL, stderr=log)
    app = shell = bus = None
    qlog = (root / 'qml.log').open('w+')
    try:
        wait((root / 'native-run/control.sock').is_socket)
        receiver, sender = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        manifest = dict(version=1, app_id=entry.name, working_directory=str(root), command=['/usr/bin/sleep', '120'], actions={})
        app = subprocess.Popen([str(launcher), '--manifest', json.dumps(manifest), '--socket', str(root / 'native-run/control.sock'),
            '--report-fd', str(sender.fileno()), '--', '/usr/bin/sleep', '120'], env=env, cwd=root,
            pass_fds=(sender.fileno(),), stdout=subprocess.DEVNULL, stderr=log)
        sender.close();receiver.settimeout(5)
        assert json.loads(receiver.recv(8192))['registered'] and receiver.recv(8192) == b''
        receiver.close()
        shutil.copy2(repo / 'dots/.config/quickshell/ii/services/CryoDConsent.qml', root / 'shell/services/CryoDConsent.qml')
        (root / 'shell/services/Notifications.qml').write_text('''pragma Singleton
import Quickshell
Singleton { signal notify(wrapper: var) }
''')
        (root / 'shell/modules/common/Config.qml').write_text('''pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
 property bool ready: true
 property JsonObject options: JsonObject { property JsonObject cryod: JsonObject { property bool enabled: true } }
}
''')
        qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.services
import qs.modules.common
ShellRoot {
 id: root
 property Notification shown: null
 Component.onCompleted: {
  CryoDConsent.executable = CLIENT;
  CryoDConsent.socketPath = SOCKET;
  CryoDConsent.peerUid = UID;
  CryoDConsent.viewActive = true;
 }
 NotificationServer {
  actionsSupported: true
  onNotification: notification => {
   notification.tracked = true;
   root.shown = notification;
   Notifications.notify({notification:notification});
  }
 }
 IpcHandler {
  target: "test"
  function status(): string { return JSON.stringify({available:CryoDConsent.available, busy:CryoDConsent.busy,
   apps:CryoDConsent.apps, error:CryoDConsent.error, message:CryoDConsent.message, prompting:CryoDConsent.prompting,
   shown:root.shown !== null, actions:root.shown?.actions.map(a => ({id:a.identifier,text:a.text})) || []}); }
  function ask(): void { CryoDConsent.ask(CryoDConsent.apps.find(a => a.app_id === "com.mekki.qml-consent.desktop")); }
  function action(name: string): void { const action = root.shown?.actions.find(a => a.identifier === name); if (action) action.invoke(); root.shown?.dismiss(); }
  function dismiss(): void { root.shown?.dismiss(); }
  function master(value: bool): void { Config.options.cryod.enabled = value; }
  function refresh(): void { CryoDConsent.refresh(); }
  function client(path: string): void { CryoDConsent.executable = path; }
 }
}
'''.replace('CLIENT', json.dumps(str(build / 'cryod-control-client'))).replace('SOCKET', json.dumps(str(root / 'native-run/control.sock'))).replace('UID', json.dumps(str(os.getuid())))
        (root / 'shell/shell.qml').write_text(qml)
        bus = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1'], stdout=subprocess.PIPE, stderr=qlog, text=True)
        address = bus.stdout.readline().strip()
        assert address.startswith('unix:')
        qenv = dict(env, HOME=str(root / 'home'), XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CACHE_HOME=str(root / 'cache'),
                    XDG_CONFIG_HOME=str(root / 'home/config'), DBUS_SESSION_BUS_ADDRESS=address,
                    QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', WAYLAND_DISPLAY='')
        for key in ('QS_CONFIG_PATH', 'QS_CONFIG_NAME'):qenv.pop(key, None)
        shell = subprocess.Popen(['qs', '-p', str(root / 'shell')], env=qenv, stdout=qlog, stderr=qlog)

        def call(method, *args):
            assert shell.poll() is None
            return subprocess.check_output(['qs', '-p', str(root / 'shell'), 'ipc', 'call', 'test', method, *args],
                                           env=qenv, text=True, stderr=subprocess.STDOUT, timeout=5).strip()

        def state():return json.loads(call('status'))
        wait(state, lambda v:v['available'] and len(v['apps']) == 1 and not v['busy'])
        original = policy.read_bytes()
        call('ask')
        displayed = wait(state, lambda v:v['shown'] and len(v['actions']) == 2)
        assert displayed['actions'] == [dict(id='yes', text='Yes'), dict(id='no', text='No')], displayed
        call('dismiss');wait(state, lambda v:not v['busy'])
        assert policy.read_bytes() == original
        print('PASS: actual Quickshell notification shows Yes/No and dismissal grants nothing', flush=True)

        call('ask');wait(state, lambda v:v['shown'])
        call('action', 'yes')
        wait(state, lambda v:v['available'] and not v['busy'] and v['apps'][0]['rule']['permissions']['freeze'] == 'allow')
        assert json.loads(policy.read_bytes())['rules'][0]['permissions']['freeze'] == 'allow'
        assert state()['message'] == 'Preference saved.'
        print('PASS: real Yes action reaches native durable save/adoption and refreshes the displayed permission', flush=True)

        call('ask');wait(state, lambda v:v['shown'])
        call('action', 'no')
        wait(state, lambda v:not v['busy'] and v['apps'][0]['rule']['permissions']['freeze'] == 'deny')
        denied = policy.read_bytes()
        row = json.loads(denied)['rules'][0]
        assert row['permissions']['freeze'] == row['permissions']['recommend'] == 'deny'
        print('PASS: real No action persists the app denial and recommendation suppression', flush=True)

        call('ask');wait(state, lambda v:v['shown'])
        call('master', 'false')
        wait(state, lambda v:not v['busy'] and not v['shown'] and not v['prompting'])
        assert policy.read_bytes() == denied and not state()['apps']
        call('master', 'true');wait(state, lambda v:v['available'] and not v['busy'])
        assert state()['apps'][0]['rule']['permissions']['freeze'] == 'deny'
        print('PASS: master Off closes the owned notification and stops its clients without changing the saved choice', flush=True)

        call('client', str(root / 'missing-client'))
        call('refresh')
        wait(state, lambda v:not v['busy'] and not v['available'] and bool(v['error']))
        assert policy.read_bytes() == denied
        call('client', str(build / 'cryod-control-client'))
        call('refresh');wait(state, lambda v:v['available'] and not v['busy'])
        print('PASS: a missing helper ends the request, reports unavailable state and recovers without a policy write', flush=True)

        app.terminate();app.wait(timeout=3)
        call('refresh');wait(state, lambda v:v['available'] and not v['busy'] and 'pid' not in v['apps'][0])
        assert state()['apps'][0]['rule']['permissions']['freeze'] == 'deny'
        assert not json.loads((root / 'native-run/status.json').read_text())['native']['effects_enabled']
        print('PASS: the durable denial stays visible after app exit; no process effects were enabled', flush=True)
    except BaseException:
        qlog.flush();qlog.seek(0);print(qlog.read()[-16000:], file=sys.stderr)
        log.flush();log.seek(0);print(log.read()[-8000:], file=sys.stderr)
        raise
    finally:
        for process in (shell, app, owner, bus):
            if process is not None and process.poll() is None:process.terminate()
            if process is not None:process.wait(timeout=15)
        qlog.close();log.close()
