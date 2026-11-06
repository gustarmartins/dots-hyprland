#!/usr/bin/env python3
"""Host-only fake: a local Unix socket server, never an Android/network connection."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

args = sys.argv[1:]
log = Path(os.environ['FAKE_ADB_LOG'])
def record(event, **values):
    with log.open('a') as output:
        output.write(json.dumps({'event': event, 'args': args, 'pid': os.getpid(),
                                'cgroup': Path('/proc/self/cgroup').read_text(),
                                'socket': os.environ.get('ADB_SERVER_SOCKET'),
                                'environment': {k: os.environ.get(k) for k in ('ADB_MDNS', 'ADB_MDNS_AUTO_CONNECT', 'ADB_USB', 'ADB_EMU')},
                                **values}) + '\n')
if len(args) == 4 and args[0] == '-L' and args[2:] == ['server', 'nodaemon']:
    path = args[1].removeprefix('localfilesystem:')
    record('server')
    if os.environ.get('FAKE_ADB_START_FAILURE'):
        raise SystemExit(7)
    with socket.socket(socket.AF_UNIX) as server:
        try: os.unlink(path)
        except FileNotFoundError: pass
        server.bind(path)
        server.listen()
        while True:
            client, _ = server.accept()
            with client:
                size = client.recv(4)
                if len(size) != 4: continue
                command = client.recv(int(size, 16)).decode()
                if command == 'host:kill':
                    client.sendall(b'OKAY')
                    break
                client.sendall(b'OKAY00040029')
    record('server_exit')
    try: os.unlink(path)
    except FileNotFoundError: pass
    raise SystemExit(0)

record('client')
specification = os.environ.get('ADB_SERVER_SOCKET', '')
if not specification.startswith('localfilesystem:'):
    raise SystemExit('FAKE refuses nonprivate ADB route')
path = specification.removeprefix('localfilesystem:')
if not Path(path).exists() and os.environ.get('FAKE_ADB_AUTO_REPLACE'):
    # Model the SDK's automatic server replacement, including daemonization.
    subprocess.Popen([sys.executable, __file__, '-L', specification, 'server', 'nodaemon'],
                     start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 2
    while not Path(path).exists() and time.monotonic() < deadline: time.sleep(.01)
with socket.socket(socket.AF_UNIX) as client:
    client.connect(path)
    client.sendall(b'000chost:version')
    if client.recv(4) != b'OKAY': raise SystemExit(2)

states_path = Path(os.environ['FAKE_ADB_STATES'])
states = json.loads(states_path.read_text())
while args[:1] in (['-s'], ['-t']): args = args[2:]
if args and args[0].startswith('wait-for-'):
    args=args[1:]
    if not args:raise SystemExit(0)
if args == ['devices'] or args == ['devices', '-l']:
    print('List of devices attached')
    for endpoint, state in states.items(): print(endpoint + '\t' + state)
elif args[0] == 'connect':
    outcome = json.loads(os.environ.get('FAKE_ADB_CONNECT_RESULTS', '{}')).get(args[1], os.environ.get('FAKE_ADB_CONNECT'))
    if outcome == 'timeout':
        time.sleep(10)
    if outcome == 'success':
        states[args[1]] = 'device'
        states_path.write_text(json.dumps(states))
        print('connected to ' + args[1])
    else:
        print('failed to connect to ' + args[1])
        raise SystemExit(1)
elif args[0] == 'disconnect':
    states.pop(args[1], None)
    states_path.write_text(json.dumps(states))
    print('disconnected')
elif args[0] == 'shell':
    print('fake shell ' + ' '.join(args[1:]))
else:
    raise SystemExit('Unexpected fake ADB action: ' + repr(args))
