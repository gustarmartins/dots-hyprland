#!/usr/bin/env python3
"""Session-scoped float/geometry controller for Hyprland's Lua dispatchers.

Existing shortcut scripts are thin entry points. Positions remain compatible with
class::title > class JSON records. A removed positions file means no saved rules;
.old files are never silently imported. Only new windows are restored by F10.
"""
import argparse
from contextlib import contextmanager
import fcntl
import json
import logging
import os
from pathlib import Path
import re
import select
import socket
import subprocess
import sys
import tempfile
import time

CONFIG = Path.home() / '.config/hypr/custom'
POSITIONS = CONFIG / 'autofloat_positions.json'
EXEMPTIONS = CONFIG / 'autofloat_exemptions.txt'
GEO = CONFIG / '.geo_restore_enabled'
SCRIPT = Path(__file__).resolve()


def runtime():
    sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    if not sig or '/' in sig:
        raise RuntimeError('Run inside the intended Hyprland session (missing instance signature).')
    base = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'hypr' / sig
    if not (base / '.socket2.sock').is_socket():
        raise RuntimeError(f'Hyprland event socket unavailable: {base}')
    folder = base / 'geometry'
    folder.mkdir(mode=0o700, exist_ok=True)
    return folder


@contextmanager
def lock(path):
    with path.open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def positions():
    data = read_json(POSITIONS, {})
    if not isinstance(data, dict):
        raise ValueError('Saved geometry must be a JSON object.')
    for key, geo in data.items():
        if not isinstance(geo, dict) or any(type(geo.get(n)) is not int for n in ('w', 'h', 'x', 'y')):
            raise ValueError(f'Invalid saved geometry for {key!r}; file preserved.')
        if geo['w'] <= 0 or geo['h'] <= 0:
            raise ValueError(f'Invalid saved size for {key!r}; file preserved.')
    return data


def hypr(*args, data=False):
    result = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=5)
    if result.returncode or result.stdout.lstrip().lower().startswith(('error', 'err:')):
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'hyprctl failed')
    return json.loads(result.stdout) if data else result.stdout


def notify(message):
    print(message, flush=True)
    subprocess.run(['notify-send', 'Window geometry', message], check=False, timeout=5)


def dispatch(address, method, **fields):
    if not re.fullmatch(r'0x[0-9a-fA-F]+', address):
        raise ValueError('Invalid window address')
    fields['window'] = f'address:{address}'
    # All strings here are controlled selectors/actions, never user window titles.
    values = ', '.join(f'{key} = {json.dumps(value)}' for key, value in fields.items())
    hypr('dispatch', f'hl.dsp.window.{method}({{ {values} }})')


def usable(mon):
    w, h = mon['width'], mon['height']
    if mon.get('transform', 0) % 2:
        w, h = h, w
    scale = mon.get('scale', 1) or 1
    left, top, right, bottom = mon.get('reserved', [0, 0, 0, 0])
    return (mon['x'] + left, mon['y'] + top,
            max(1, round(w / scale) - left - right),
            max(1, round(h / scale) - top - bottom))


def target_geometry(geo, mon):
    x, y, mw, mh = usable(mon)
    w, h = min(geo['w'], mw), min(geo['h'], mh)
    gx = min(max(mon['x'] + geo['x'], x), x + mw - w)
    gy = min(max(mon['y'] + geo['y'], y), y + mh - h)
    return w, h, gx, gy


def lookup(saved, client):
    cls = client.get('class') or client.get('initialClass', '')
    for key in (f"{cls}::{client.get('title', '')}", cls):
        if key in saved:
            return key, saved[key]
    return None, None


def exempt(client):
    if not EXEMPTIONS.exists():
        return False
    for line in EXEMPTIONS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        try:
            if line.startswith('title:'):
                if re.search(line[6:], client.get('title', '')):
                    return True
            elif re.fullmatch(line, client.get('class', '')):
                return True
        except re.error:
            logging.warning('Ignoring invalid exemption regex: %r', line)
    return False


def identity(client):
    return [client.get('pid'), client.get('initialClass', client.get('class'))]


def eligible(client):
    return bool(client.get('mapped', True) and not client.get('hidden', False)
                and not client.get('fullscreen', 0) and not client.get('fullscreenClient', 0)
                and not client.get('pinned', False))


def rpc(folder, command):
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(10)
        conn.connect(str(folder / 'control.sock'))
        conn.sendall((command + '\n').encode())
        result = b''
        while not result.endswith(b'\n'):
            block = conn.recv(65536)
            if not block:
                raise RuntimeError('Geometry controller disconnected')
            result += block
    reply = json.loads(result)
    if 'error' in reply:
        raise RuntimeError(reply['error'])
    return reply


def alive(folder):
    try:
        return rpc(folder, 'status')
    except (OSError, RuntimeError):
        return None


def ensure(folder):
    if alive(folder):
        return
    with (folder / 'daemon.log').open('a') as log:
        proc = subprocess.Popen([sys.executable, str(SCRIPT), 'serve'], stdin=subprocess.DEVNULL,
                                stdout=log, stderr=log, start_new_session=True)
    for _ in range(60):
        if alive(folder):
            return
        if proc.poll() is not None:
            break
        time.sleep(.05)
    raise RuntimeError(f'Geometry controller failed to start; see {folder / "daemon.log"}')


class Controller:
    def __init__(self, folder):
        self.folder = folder
        self.master_file = folder / 'master.json'
        self.owned = read_json(self.master_file, None)
        self.opened = {}
        self.running = True

    def status(self):
        result = dict(geometry=GEO.exists(), master=self.owned is not None, pid=os.getpid())
        try:
            result['saved'] = len(positions())
        except (OSError, ValueError) as error:
            result.update(saved=None, data_error=str(error))
        return result

    def persist_master(self):
        if self.owned is None:
            self.master_file.unlink(missing_ok=True)
        else:
            atomic_write(self.master_file, json.dumps(self.owned))

    def float(self, client, own=False):
        if not client.get('floating'):
            dispatch(client['address'], 'float', action='enable')
            if own and self.owned is not None:
                self.owned[client['address']] = identity(client)
                self.persist_master()

    def apply(self, address):
        tracked = self.opened.get(address)
        if not tracked or time.monotonic() - tracked['time'] > 3:
            return
        clients = hypr('clients', '-j', data=True)
        client = next((c for c in clients if c['address'] == address), None)
        if not client or not eligible(client):
            return
        if not client.get('class') and not client.get('initialClass'):
            return
        key, geo = lookup(positions(), client) if GEO.exists() else (None, None)
        if key:
            # A late title can refine an app fallback, but never revert a match.
            if key in tracked['applied'] or (tracked['specific'] and '::' not in key):
                return
        elif tracked['applied'] or self.owned is None:
            return
        monitors = hypr('monitors', '-j', data=True)
        mon = next((m for m in monitors if m['id'] == client.get('monitor')), None)
        if mon is None:
            return
        self.float(client, own=not bool(key))
        if key and self.owned is not None:
            self.owned.pop(address, None)  # Saved geometry owns this float now.
            self.persist_master()
        if not key and exempt(client):
            tracked['applied'].add('@master')
            return
        if geo is None:
            x, y, mw, mh = usable(mon)
            w, h = min(1200, mw), min(800, mh)
            geo = dict(w=w, h=h, x=x-mon['x']+(mw-w)//2, y=y-mon['y']+(mh-h)//2)
        w, h, x, y = target_geometry(geo, mon)
        dispatch(address, 'resize', x=w, y=h, relative=False)
        dispatch(address, 'move', x=x, y=y, relative=False)
        # Preserve the configured animation/no_anim rules and existing z-order.
        tracked['applied'].add(key or '@master')
        tracked['specific'] = bool(key and '::' in key)

    def command(self, command):
        if command == 'status':
            return self.status()
        if command == 'stop':
            self.running = False
            return {'stopped': True}
        if command != 'toggle-master':
            raise ValueError(f'Unknown controller command: {command}')
        clients = hypr('clients', '-j', data=True)
        if self.owned is None:
            workspace = hypr('activeworkspace', '-j', data=True)['id']
            self.owned = {}
            self.persist_master()
            for client in clients:
                if client['workspace']['id'] == workspace and eligible(client):
                    self.float(client, own=True)
        else:
            for client in clients:
                if (self.owned.get(client['address']) == identity(client)
                        and client.get('floating') and eligible(client)):
                    dispatch(client['address'], 'float', action='disable')
            self.owned = None
            self.persist_master()
        return self.status()

    def event(self, line):
        name, _, payload = line.partition('>>')
        address = '0x' + payload.split(',', 1)[0].removeprefix('0x')
        if name == 'openwindow':
            self.opened[address] = dict(time=time.monotonic(), due=time.monotonic()+.08,
                                        applied=set(), specific=False, retries=0)
        elif name == 'windowtitlev2' and address in self.opened:
            if time.monotonic() - self.opened[address]['time'] < 3:
                self.opened[address]['due'] = time.monotonic()+.05
        elif name == 'closewindow':
            self.opened.pop(address, None)
            if self.owned is not None and address in self.owned:
                self.owned.pop(address)
                self.persist_master()

    def serve(self):
        # Lifetime lock prevents competing listeners, with no PID-based kills.
        with lock(self.folder / 'daemon.lock'), socket.socket(socket.AF_UNIX) as events, socket.socket(socket.AF_UNIX) as server:
            events.connect(str(self.folder.parent / '.socket2.sock'))
            control = self.folder / 'control.sock'
            control.unlink(missing_ok=True)
            server.bind(str(control))
            server.listen(4)
            buffer = b''
            try:
                while self.running:
                    due = [t['due'] for t in self.opened.values() if t['due'] is not None]
                    wait = max(0, min(due)-time.monotonic()) if due else None
                    ready, _, _ = select.select([events, server], [], [], wait)
                    if events in ready:
                        block = events.recv(65536)
                        if not block:
                            break  # Compositor exited: no orphan process/reconnect to another session.
                        buffer += block
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            self.event(line.decode(errors='replace'))
                    if server in ready:
                        conn, _ = server.accept()
                        with conn:
                            conn.settimeout(2)
                            try:
                                command = conn.recv(1024).decode().strip()
                                reply = self.command(command)
                            except Exception as error:
                                logging.exception('Controller command failed')
                                reply = {'error': str(error)}
                            conn.sendall((json.dumps(reply)+'\n').encode())
                    for address, tracked in list(self.opened.items()):
                        if tracked['due'] is not None and tracked['due'] <= time.monotonic():
                            tracked['due'] = None
                            try:
                                self.apply(address)
                            except Exception:
                                logging.exception('Could not apply geometry to %s', address)
                            if not tracked['applied'] and tracked['retries'] < 3:
                                tracked['retries'] += 1
                                tracked['due'] = time.monotonic()+.15
            finally:
                control.unlink(missing_ok=True)


def save(scope):
    client = hypr('activewindow', '-j', data=True)
    cls = client.get('class')
    if not cls:
        raise ValueError('No active window found.')
    title = client.get('title', '')
    if scope == 'window' and not title:
        raise ValueError('Window has no title; use Super+Ctrl+F11 for an app rule.')
    key = f'{cls}::{title}' if scope == 'window' else cls
    with lock(CONFIG / '.geometry-data.lock'):
        data = positions()
        if key in data:
            del data[key]
            message = f'Removed {scope} geometry: {key}'
        else:
            if not eligible(client):
                raise ValueError('Leave fullscreen before saving window geometry.')
            mon = next((m for m in hypr('monitors', '-j', data=True) if m['id'] == client['monitor']), None)
            if mon is None:
                raise ValueError('Window monitor is unavailable; geometry was not saved.')
            w, h = client['size']
            x, y = client['at']
            data[key] = dict(w=w, h=h, x=x-mon['x'], y=y-mon['y'])
            message = f'Saved {scope} geometry: {key} ({w}×{h})'
        atomic_write(POSITIONS, json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    notify(message + ('; restoration is OFF (Super+F10)' if not GEO.exists() else ''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['serve', 'ensure', 'stop', 'status', 'toggle-geo', 'toggle-master', 'save-app', 'save-window'])
    args = parser.parse_args()
    folder = runtime()
    if args.action == 'serve':
        Controller(folder).serve()
        return
    if args.action.startswith('save-'):
        save(args.action.removeprefix('save-'))
        return
    with lock(folder / 'command.lock'):
        if args.action == 'status':
            print(json.dumps(alive(folder) or dict(geometry=GEO.exists(), master=(folder/'master.json').exists(), saved=len(positions()), pid=None), indent=2))
            return
        if args.action == 'stop':
            if alive(folder):
                rpc(folder, 'stop')
            return
        if args.action == 'toggle-geo':
            if GEO.exists():
                GEO.unlink()
            else:
                count = len(positions())  # Fail before enabling malformed data.
                ensure(folder)
                GEO.touch()
            notify('Geometry Restore: ' + ('ON' if GEO.exists() else 'OFF') +
                   (' — no saved positions; use Super+Ctrl+F11/F12 to save' if GEO.exists() and not count else ''))
        elif args.action == 'toggle-master':
            ensure(folder)
            state = rpc(folder, 'toggle-master')
            notify('Master Float: ' + ('ON' if state['master'] else 'OFF'))
        if GEO.exists() or (folder / 'master.json').exists():
            ensure(folder)
        elif alive(folder):
            rpc(folder, 'stop')


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        logging.error('%s', error)
        if len(sys.argv) < 2 or sys.argv[1] != 'serve':
            notify(str(error))
        sys.exit(1)
