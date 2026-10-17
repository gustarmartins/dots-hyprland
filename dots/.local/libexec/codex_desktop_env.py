"""Discover this user's local desktop without assuming a display number."""
import os
from pathlib import Path
import re
import stat
import subprocess
import time

KEYS = ('DISPLAY', 'WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS')

def desktop_environment(wait_seconds=0):
    deadline = time.monotonic() + wait_seconds
    while True:
        result = subprocess.run(['systemctl', '--user', 'show-environment'], capture_output=True, text=True, timeout=3)
        values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
        env = {key: values[key] for key in KEYS if key in values}
        runtime = Path(env.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        if runtime.is_dir() and runtime.stat().st_uid == os.getuid():
            env['XDG_RUNTIME_DIR'] = str(runtime)
            candidates = [runtime / env['WAYLAND_DISPLAY']] if env.get('WAYLAND_DISPLAY') else list(runtime.glob('wayland-*'))
            candidates = [p for p in candidates if p.exists() and stat.S_ISSOCK(p.stat().st_mode) and p.stat().st_uid == os.getuid()]
            if len(candidates) == 1:
                env['WAYLAND_DISPLAY'] = candidates[0].name
            else:
                env.pop('WAYLAND_DISPLAY', None)
        else:
            env.pop('WAYLAND_DISPLAY', None)
        display = re.fullmatch(r':(\d+)(?:\.\d+)?', env.get('DISPLAY', ''))
        if not display or not Path('/tmp/.X11-unix/X' + display[1]).exists():
            env.pop('DISPLAY', None)
        if env.get('DISPLAY') or env.get('WAYLAND_DISPLAY') or time.monotonic() >= deadline:
            return env
        time.sleep(.5)
