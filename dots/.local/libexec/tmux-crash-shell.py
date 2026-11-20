#!/usr/bin/env python3
"""Return a crashed tmux pane to a shell. Never relaunch its old command."""
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    pane = sys.argv[1]
    if not re.fullmatch(r'%[0-9]+', pane):
        raise SystemExit('Invalid pane')
    # Hooks and tests inherit the owning server's socket, including private servers.
    socket = os.environ['TMUX'].rsplit(',', 2)[0]
    tmux = ['tmux', '-S', socket]
    row = subprocess.check_output(tmux + ['display-message', '-p', '-t', pane,
        '#{pane_dead}\t#{pane_dead_signal}\t#{pane_dead_status}\t#{pane_start_path}\t#{session_path}'], text=True).strip('\n').split('\t')
    dead, signal, status, start, session = row
    if dead != '1':
        return
    # Intentional normal exit, HUP and TERM keep their usual semantics.
    if signal not in ('4', '6', '7', '8', '9', '11') and not (not signal and status and int(status) != 0):
        return
    cwd = next((p for p in (start, session, str(Path.home())) if p and Path(p).is_dir()))
    # No -k: tmux refuses if the owner has already revived this pane.
    subprocess.run(tmux + ['respawn-pane', '-t', pane, '-c', cwd, '/usr/bin/zsh', '-l'], check=True)


if __name__ == '__main__':
    main()
