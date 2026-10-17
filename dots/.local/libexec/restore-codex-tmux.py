#!/usr/bin/env python3
"""Restore explicit Codex threads, with an optional owner-authorized continuation."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import time

from codex_desktop_env import desktop_environment


def writer_lock_is_held(thread_id):
    """Return whether another process currently owns this thread's writer lock."""
    path = Path.home() / '.codex/thread-writer-locks' / f'{thread_id}.lock'
    try:
        fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
    except FileNotFoundError:
        return False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        else:
            fcntl.flock(fd, fcntl.LOCK_UN)
            return False
    finally:
        os.close(fd)


def launch_session(tmux, row, argv, boot, test=False):
    """Retry only our dead pane; never kill a process or type into a shell."""
    name = row['name']
    if not test and writer_lock_is_held(row['id']):
        return {'name': name, 'status': 'already active; writer lock held'}
    other_panes = subprocess.run(tmux + ['list-panes', '-a', '-F', '#{session_name}\t#{@codex_session}'], capture_output=True, text=True)
    for line in other_panes.stdout.splitlines():
        fields = line.split('\t')
        if len(fields) == 2 and fields[1] == row['id'] and fields[0] != name:
            return {'name': name, 'status': 'thread already mapped in another pane; untouched'}
    existing = subprocess.run(tmux + ['list-sessions', '-F', '#{session_name}'], capture_output=True, text=True)
    pane = None
    if name in existing.stdout.splitlines():
        existing_panes = subprocess.check_output(tmux + ['list-panes', '-s', '-t', '=' + name,
            '-F', '#{pane_id}\t#{pane_dead}\t#{@codex_session}\t#{@codex_restore_boot}\t#{pane_dead_status}'], text=True).splitlines()
        if len(existing_panes) == 1:
            fields = existing_panes[0].split('\t')
            if len(fields) == 5 and fields[1:4] == ['1', row['id'], boot] and fields[4].isdigit() and int(fields[4]) != 0:
                pane = fields[0]
        if pane is None:
            return {'name': name, 'status': 'existing live or unrelated pane; untouched'}
    if not Path(row['cwd']).is_dir() or not shutil.which(argv[0]):
        return {'name': name, 'status': 'missing directory or executable'}
    # Retain a failed process as a dead pane, not an interactive shell. A retry
    # can then use respawn-pane WITHOUT -k, which refuses any live process.
    setup = shlex.join(tmux + ['set-option', '-w', '-t']) + ' "$TMUX_PANE" remain-on-exit on'
    command = '/usr/bin/zsh -f' if test else setup + ' && exec ' + shlex.join(argv)
    if pane:
        if writer_lock_is_held(row['id']):
            return {'name': name, 'status': 'already active; writer lock held'}
        result = subprocess.run(tmux + ['respawn-pane', '-t', pane, '-c', row['cwd'], command], capture_output=True, text=True)
        return {'name': name, 'status': 'resume retried' if result.returncode == 0 else 'pane changed before retry; untouched'}
    session = subprocess.check_output(tmux + ['new-session', '-d', '-P', '-F', '#{session_id}',
        '-s', name, '-n', name, '-c', row['cwd'], command], text=True).strip()
    subprocess.run(tmux + ['set-option', '-t', session, '@codex_session', row['id']], check=True)
    subprocess.run(tmux + ['set-option', '-t', session, '@codex_restore_boot', boot], check=True)
    subprocess.run(tmux + ['set-window-option', '-t', session + ':0', 'automatic-rename', 'off'], check=True)
    if test:
        actual = subprocess.check_output(tmux + ['list-panes', '-t', session, '-F', '#{session_name}\t#{pane_current_path}\t#{@codex_session}'], text=True).strip()
        assert actual == f"{name}\t{row['cwd']}\t{row['id']}", actual
    return {'name': name, 'status': 'placeholder verified' if test else 'resume launched'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--test', action='store_true', help='isolated tmux, inert shell placeholders')
    parser.add_argument('--armed', action='store_true', help='consume the one-reboot authorization after restoration')
    parser.add_argument('--now', action='store_true', help='restore immediately when explicitly requested by the owner')
    args = parser.parse_args()
    # Boot restoration was revoked by the owner on 2026-10-16. Keep saved
    # session mappings for explicit manual recovery, never for login hooks.
    if not (args.now or args.plan or args.test):
        print('Automatic Codex restoration is disabled. Use --now only for explicitly requested manual recovery.')
        return
    if args.armed:
        parser.error('Automatic reboot restoration is disabled; --armed is no longer supported.')
    root = Path.home() / '.local/state/codex-tmux'
    armed = root / 'reboot-restore.armed'
    if args.armed and not armed.exists():
        print('No reboot restoration is armed.')
        return
    config = json.loads((root / 'restore.json').read_text())
    for key in ('id', 'name'):
        if len({r[key] for r in config['sessions']}) != len(config['sessions']):
            raise ValueError('Duplicate restoration ' + key)
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    commands = []
    for row in config['sessions']:
        if not re.fullmatch(r'[^:.\x00-\x1f\x7f]{1,100}', row['name']):
            raise ValueError('Invalid tmux session name')
        if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', row['id']):
            raise ValueError('Invalid Codex session id')
        # Read the final persisted settings, including changes made after arming.
        db = Path.home() / '.codex/state_5.sqlite'
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as connection:
            connection.row_factory = sqlite3.Row
            latest = connection.execute('SELECT cwd, model, reasoning_effort, approval_mode, sandbox_policy FROM threads WHERE id=?', (row['id'],)).fetchone()
        if latest is None:
            raise ValueError('Saved Codex thread is missing: ' + row['id'])
        row = {**row, **dict(latest)}
        argv = ['/usr/bin/codex', 'resume', row['id'], '--no-daemon', '-C', row['cwd']]
        if row.get('model'):
            argv += ['-m', row['model']]
        if row.get('reasoning_effort'):
            argv += ['-c', 'model_reasoning_effort=' + json.dumps(row['reasoning_effort'])]
        if row.get('approval_mode'):
            argv += ['-a', row['approval_mode']]
        policy = json.loads(row.get('sandbox_policy', '{}')).get('type')
        if policy in {'disabled', 'danger-full-access'}:
            argv += ['-s', 'danger-full-access']
        elif policy in {'read-only', 'workspace-write'}:
            argv += ['-s', policy]
        if row.get('resume_prompt'):
            if not isinstance(row['resume_prompt'], str):
                raise ValueError('Invalid Codex continuation prompt')
            argv.append(row['resume_prompt'])
        commands.append((row, argv))
    if args.plan:
        print(json.dumps([{'name': r['name'], 'cwd': r['cwd'], 'argv': a} for r, a in commands], indent=2))
        return
    if not args.test and not args.now and boot == config['saved_boot_id']:
        print('Prepared for the next boot; current terminals remain unchanged.')
        return
    with (root / 'restore.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        tmux = ['/usr/bin/tmux']
        if args.test:
            tmux += ['-L', f'codex-restore-test-{os.getpid()}', '-f', '/dev/null']
        results = []
        # Login may import the desktop after the persistent server starts.
        env = desktop_environment(wait_seconds=0 if args.test else 30)
        os.environ.update(env)
        # On a headless boot no server exists yet; the first session inherits
        # this environment. Update an existing server only when available.
        if subprocess.run(tmux + ['list-sessions'], capture_output=True).returncode == 0:
            for key, value in env.items():
                subprocess.run(tmux + ['set-environment', '-g', key, value], check=True)
        try:
            for row, argv in commands:
                results.append(launch_session(tmux, row, argv, boot, test=args.test))
                if not args.test:
                    time.sleep(.3)
            if not args.test:
                deadline = time.monotonic() + 45
                pending = {row['id'] for row, argv in commands}
                while pending and time.monotonic() < deadline:
                    pending = {tid for tid in pending if not writer_lock_is_held(tid)}
                    if pending:
                        time.sleep(1)
                for (row, argv), result in zip(commands, results):
                    result['writer_verified'] = writer_lock_is_held(row['id'])
            report = {'boot': boot, 'test': args.test, 'sessions': results}
            destination = root / ('test-result.json' if args.test else 'last-restore.json')
            temporary = destination.with_suffix('.tmp')
            temporary.write_text(json.dumps(report, indent=2) + '\n')
            temporary.replace(destination)
            print(json.dumps(report))
            if args.armed and not args.test and all(r.get('writer_verified') for r in results):
                armed.unlink(missing_ok=True)
            elif args.armed and not args.test:
                raise RuntimeError('Some Codex writers did not start; inspect last-restore.json. Authorization remains armed.')
        finally:
            if args.test:
                subprocess.run(tmux + ['kill-server'], capture_output=True)


if __name__ == '__main__':
    main()
