"""Real signal tests on a private server; never touch owner sessions."""
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid

import pytest

HELPER = Path(__file__).resolve().parents[1] / 'dots/.local/libexec/tmux-crash-shell.py'

@pytest.fixture
def server(tmp_path):
    base = ['tmux', '-L', 'crash-test-' + uuid.uuid4().hex, '-f', '/dev/null']
    def run(*args):
        return subprocess.check_output(base + list(args), text=True, timeout=5).strip()
    run('new-session', '-d', '-s', 'anchor', '/usr/bin/zsh', '-f')
    run('set', '-g', 'remain-on-exit', 'failed')
    run('set-hook', '-g', 'pane-died[90]', f'run-shell -b "python3 \'{HELPER}\' #{{pane_id}}"')
    yield run
    subprocess.run(base + ['kill-server'], capture_output=True, timeout=5)

@pytest.mark.parametrize('kill_root', [False, True])
def test_kill_leaves_same_pane_with_shell(server, tmp_path, kill_root):
    marker = tmp_path / 'child'
    script = tmp_path / 'parent.sh'
    script.write_text(f'#!/bin/sh\nsleep 60 &\necho $! > "{marker}"\nwait\nexec /usr/bin/zsh -f\n')
    pane = server('new-window', '-d', '-P', '-F', '#{pane_id}', '-c', str(tmp_path), '/bin/sh', str(script))
    for _ in range(50):
        if marker.exists(): break
        time.sleep(.05)
    pid = int(server('display-message', '-p', '-t', pane, '#{pane_pid}')) if kill_root else int(marker.read_text())
    os.kill(pid, signal.SIGKILL)
    for _ in range(60):
        state = server('display-message', '-p', '-t', pane, '#{pane_dead}:#{pane_current_command}:#{pane_current_path}')
        if state == f'0:zsh:{tmp_path}': break
        time.sleep(.05)
    assert state == f'0:zsh:{tmp_path}'


def test_normal_exit_still_closes(server):
    pane = server('new-window', '-d', '-P', '-F', '#{pane_id}', '/bin/sh', '-c', 'sleep .1; exit 0')
    for _ in range(50):
        panes = server('list-panes', '-a', '-F', '#{pane_id}').splitlines()
        if pane not in panes: break
        time.sleep(.05)
    assert pane not in panes
