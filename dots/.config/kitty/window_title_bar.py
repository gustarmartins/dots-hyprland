"""Label the actual local terminal route without replacing application titles."""
from pathlib import Path
from time import monotonic
from kitty.fast_data_types import get_boss

_cache = {}

def draw_window_title(data):
    window = get_boss().window_id_map.get(data.window_id)
    if window is None:
        return '[?]'
    key = (window.child.pid, data.title)
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
    _cache[data.window_id] = (key, now, marker)
    return marker
