"""Label the actual local terminal route without replacing application titles."""
import json
import os
from pathlib import Path
from time import monotonic, time
from kitty.fast_data_types import get_boss

_cache = {}
_snapshot_cache = (0, {})

def session_pid(window_id, shell_pid):
    global _snapshot_cache
    now = monotonic()
    if now - _snapshot_cache[0] >= 2:
        try:
            path = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'agent-monitor/snapshot.json'
            with path.open() as handle:
                raw = handle.read(4 * 1024 * 1024 + 1)
            data = json.loads(raw) if len(raw) <= 4 * 1024 * 1024 else {}
        except (OSError, ValueError):
            data = {}
        _snapshot_cache = (now, data)
    data = _snapshot_cache[1]
    if not data.get('config', {}).get('enabled') or not data.get('config', {}).get('titles'):
        return None
    if not 0 <= time() - data.get('timestamp', 0) < 20:
        return None
    candidates = [client for session in data.get('sessions', []) for client in session.get('clients', [])]
    candidates += data.get('unmatched_clients', [])
    matched = set()
    for client in candidates:
        if not any(w['id'] == window_id and w['pid'] == shell_pid for w in client.get('kitty', [])):
            continue
        try:
            birth = int((Path('/proc') / str(client['pid']) / 'stat').read_text().rsplit(')', 1)[1].split()[19])
            if birth == client['start_ticks']:
                matched.add(client['pid'])
        except (OSError, ValueError, IndexError):
            continue
    return next(iter(matched)) if len(matched) == 1 else None


def draw_window_title(data):
    window = get_boss().window_id_map.get(data.window_id)
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
