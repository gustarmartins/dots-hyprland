#!/usr/bin/env python3
"""Restore an explicit set of Codex threads after reboot without new prompts."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--test', action='store_true', help='isolated tmux, inert shell placeholders')
    args = parser.parse_args()
    root = Path.home() / '.local/state/codex-tmux'
    config = json.loads((root / 'restore.json').read_text())
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    commands = []
    for row in config['sessions']:
        if not re.fullmatch(r'[a-z0-9-]+', row['name']):
            raise ValueError('Invalid tmux session name')
        if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', row['id']):
            raise ValueError('Invalid Codex session id')
        argv = ['/usr/bin/codex', 'resume', row['id'], '-C', row['cwd']]
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
        commands.append((row, argv))
    if args.plan:
        print(json.dumps([{'name': r['name'], 'cwd': r['cwd'], 'argv': a} for r, a in commands], indent=2))
        return
    if not args.test and boot == config['saved_boot_id']:
        print('Prepared for the next boot; current terminals remain unchanged.')
        return
    with (root / 'restore.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        tmux = ['/usr/bin/tmux']
        if args.test:
            tmux += ['-L', f'codex-restore-test-{os.getpid()}', '-f', '/dev/null']
        results = []
        try:
            for row, argv in commands:
                name = row['name']
                existing = subprocess.run(tmux + ['list-sessions', '-F', '#{session_name}'], capture_output=True, text=True)
                if name in existing.stdout.splitlines():
                    results.append({'name': name, 'status': 'already exists; untouched'})
                    continue
                if not Path(row['cwd']).is_dir() or not shutil.which(argv[0]):
                    results.append({'name': name, 'status': 'missing directory or executable'})
                    continue
                # A shell remains available if authentication or Codex startup fails.
                command = '/usr/bin/zsh -f' if args.test else shlex.join(argv) + '; exec /usr/bin/zsh'
                session = subprocess.check_output(tmux + ['new-session', '-d', '-P', '-F', '#{session_id}',
                    '-s', name, '-n', name, '-c', row['cwd'], command], text=True).strip()
                subprocess.run(tmux + ['set-option', '-t', session, '@codex_session', row['id']], check=True)
                subprocess.run(tmux + ['set-window-option', '-t', session + ':0', 'automatic-rename', 'off'], check=True)
                results.append({'name': name, 'status': 'placeholder verified' if args.test else 'resume launched'})
                if not args.test:
                    time.sleep(.3)
            report = {'boot': boot, 'test': args.test, 'sessions': results}
            destination = root / ('test-result.json' if args.test else 'last-restore.json')
            temporary = destination.with_suffix('.tmp')
            temporary.write_text(json.dumps(report, indent=2) + '\n')
            temporary.replace(destination)
            print(json.dumps(report))
        finally:
            if args.test:
                subprocess.run(tmux + ['kill-server'], capture_output=True)


if __name__ == '__main__':
    main()
