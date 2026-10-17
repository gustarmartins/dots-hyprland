#!/usr/bin/env python3
"""Private D-Bus, synthetic email, real Python bridge and real QML service."""
import json
import dbus
import os
from pathlib import Path
import select
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
run = Path(tempfile.mkdtemp(prefix='qs-mail-native-test-'))
runtime = run / 'runtime'; runtime.mkdir(mode=0o700)
config = run / 'config/qs-mail'; config.mkdir(parents=True)
cfg = dict(enabled=True, notifications=True, preview=True, codes=True, links=True, accounts=['account1'])
(config / 'config.json').write_text(json.dumps(cfg))
history = run / 'history.json'; history.write_text('[]')
env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(run / 'config'), TEST_HISTORY=str(history), QT_QPA_PLATFORM='offscreen')
for key in ('DISPLAY', 'WAYLAND_DISPLAY'): env.pop(key, None)
assert f'/run/user/{os.getuid()}/bus' not in env.get('DBUS_SESSION_BUS_ADDRESS', ''), 'Use dbus-run-session'
fixture = ROOT / 'tests/notification-fixture/shell.qml'
log = (run / 'shell.log').open('w')
shell = subprocess.Popen(['qs', '-p', str(fixture)], env=env, stdout=log, stderr=subprocess.STDOUT)
native = None
def call(*args):
    p = subprocess.run(['qs', '-p', str(fixture), 'ipc', 'call', 'audit', *args], env=env, capture_output=True, text=True, timeout=4)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()
def until(fn, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = fn()
            if value: return value
        except (RuntimeError, ValueError, OSError): pass
        time.sleep(.05)
    raise AssertionError('timed out')
def state(): return json.loads(call('status'))
def send(data):
    raw = json.dumps(data).encode(); native.stdin.write(struct.pack('=I', len(raw)) + raw); native.stdin.flush()
def receive():
    assert select.select([native.stdout], [], [], 5)[0], 'native response timed out'
    size = struct.unpack('=I', native.stdout.read(4))[0]
    return json.loads(native.stdout.read(size))
def set_config(value):
    temp = config / 'new.json'; temp.write_text(json.dumps(value)); temp.replace(config / 'config.json')
    call('mailConfig', 'json:' + json.dumps(value))
try:
    until(lambda: state()['ready'])
    call('mailConfig', 'json:' + json.dumps(cfg))
    native = subprocess.Popen(['python3', str(ROOT / 'dots/.local/lib/qs-mail/bridge.py'), 'native'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert receive()['type'] == 'config'
    data = dict(type='mail', key='fixture-1', account='account1', messageId=7, sender='Synthetic fixture', subject='Sign in', date=time.time()*1000,
                bodies=[dict(type='text/html',text='<p>Your verification code: 123456</p><a href="https://example.invalid/verify">Sign in</a>')])
    send(data)
    record = until(lambda: state()['list'] and state()['list'][0])
    assert [a['identifier'] for a in record['actions']] == ['qs-mail-open', 'qs-mail-code', 'qs-mail-link-0']
    call('action', str(record['id']), 'qs-mail-code')
    assert call('clipboardEquals', '123456') == 'true'
    time.sleep(.2)
    assert json.loads(history.read_text()) == [], 'mail content persisted in notification history'
    bus = dbus.SessionBus()
    notify = dbus.Interface(bus.get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications'), 'org.freedesktop.Notifications')
    notify.Notify('Thunderbird', 0, 'thunderbird', 'Generic duplicate', 'Synthetic', dbus.Array([], signature='s'), dbus.Dictionary({}, signature='sv'), -1)
    time.sleep(.1)
    assert len(state()['list']) == 1, 'generic Thunderbird duplicate was shown'

    runtime_state = (runtime / 'qs-mail/state.json').read_text()
    assert '123456' not in runtime_state and 'example.invalid' not in runtime_state
    send(data); time.sleep(.2); assert len(state()['list']) == 1, 'duplicate mail delivered'
    cfg['codes'] = False; set_config(cfg); receive()
    assert 'qs-mail-code' not in [a['identifier'] for a in state()['list'][0]['actions']]
    cfg['accounts'] = []; set_config(cfg); receive()
    until(lambda: not state()['list'])
    send({**data,'key':'fixture-2'}); time.sleep(.2); assert not state()['list']
    cfg['enabled'] = False; set_config(cfg)
    native.wait(timeout=5)
    assert native.returncode == 0 and not (runtime / 'qs-mail/bridge.sock').exists()
    assert not json.loads((runtime / 'qs-mail/state.json').read_text())['connected']
    print('PASS: native framing → real QML actions, clipboard, dedup, private persistence, live feature/account gates, disable exits host and removes socket')
finally:
    if native and native.poll() is None: native.terminate(); native.wait(timeout=5)
    shell.terminate(); shell.wait(timeout=5); log.close()
print(run)
