"""Label the actual local terminal route without replacing application titles."""
import json
import os
from pathlib import Path
from time import monotonic, time
from kitty.fast_data_types import get_boss

_cache = {}
_snapshot_deadline = 0
_snapshot_version = None
_snapshot_timestamp = 0
_window_clients = {}


def refresh_title_index():
    global _snapshot_deadline, _snapshot_version, _snapshot_timestamp, _window_clients
    now = monotonic()
    if now < _snapshot_deadline:
        return
    _snapshot_deadline = now + 2
    path = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'agent-monitor/snapshot.json'
    try:
        with path.open('rb') as handle:
            stat = os.fstat(handle.fileno())
            version = (stat.st_ino, stat.st_mtime_ns, stat.st_size)
            if version == _snapshot_version:
                return
            limit = 4 * 1024 * 1024
            raw = handle.read(limit + 1) if stat.st_size <= limit else b''
            data = json.loads(raw) if 0 < len(raw) <= limit else {}
        config = data.get('config', {})
        index = {}
        if config.get('enabled') and config.get('titles'):
            def add(clients):
                for client in clients:
                    for window in client.get('kitty', []):
                        index.setdefault((window['id'], window['pid']), set()).add((client['pid'], client['start_ticks']))
            for session in data.get('sessions', []):
                add(session.get('clients', []))
            add(data.get('unmatched_clients', []))
        _window_clients = index
        _snapshot_timestamp = float(data.get('timestamp', 0))
        _snapshot_version = version
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        _snapshot_version = None
        _snapshot_timestamp = 0
        _window_clients = {}

def session_pid(window_id, shell_pid):
    refresh_title_index()
    if not 0 <= time() - _snapshot_timestamp < 20:
        return None
    matched = set()
    for pid, start in _window_clients.get((window_id, shell_pid), ()):
        try:
            birth = int((Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()[19])
            if birth == start:
                matched.add(pid)
        except (OSError, ValueError, IndexError):
            continue
    return next(iter(matched)) if len(matched) == 1 else None


def draw_window_title(data):
    windows = get_boss().window_id_map
    if len(_cache) > len(windows) + 16:
        for obsolete in _cache.keys() - windows.keys():
            del _cache[obsolete]
    window = windows.get(data.window_id)
    if window is None:
        return '[?]'
    key = window.child.pid
    cached = _cache.get(data.window_id)
    now = monotonic()
    if cached and cached[0] == key and now - cached[1] < 2:
        return cached[2]
    try:
        foreground = int((Path('/proc') / str(window.child.pid) / 'stat').read_text().rsplit(')', 1)[1].split()[5])
    except (OSError, ValueError, IndexError):
        foreground = -1
    processes = [{'pid': foreground}] if foreground > 0 else (window.child.foreground_processes or [{'pid': window.child.pid}])
    names = set()
    for process in processes:
        try:
            names.add((Path('/proc') / str(process['pid']) / 'exe').resolve(strict=True).name)
        except OSError:
            continue
    marker = '[TMUX]' if 'tmux' in names else '[SSH]' if names & {'ssh', 'mosh-client'} else '[DIRECT]' if names else '[?]'
    pid = session_pid(data.window_id, window.child.pid)
    if pid is not None:
        marker = marker[:-1] + f' · PID {pid}]'
    _cache[data.window_id] = (key, now, marker)
    return marker
