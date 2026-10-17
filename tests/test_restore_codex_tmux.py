"""Isolated retry regressions; no real Codex process or rollout is loaded."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'dots/.local/libexec'))

spec = importlib.util.spec_from_file_location('restore', Path(__file__).resolve().parents[1] / 'dots/.local/libexec/restore-codex-tmux.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.tmux = ['/usr/bin/tmux', '-L', f'codex-retry-test-{os.getpid()}', '-f', '/dev/null']
        self.row = {'name': 'Exact session name', 'id': '00000000-0000-0000-0000-000000000001', 'cwd': '/tmp'}
        self.lock = patch.object(restore, 'writer_lock_is_held', return_value=False)
        self.lock.start()

    def tearDown(self):
        subprocess.run(self.tmux + ['kill-server'], capture_output=True)
        self.lock.stop()

    def call(self, *args):
        return subprocess.check_output(self.tmux + list(args), text=True).strip()

    def launch(self, argv):
        return restore.launch_session(self.tmux, self.row, argv, 'test-boot')['status']

    def wait_dead(self):
        for _ in range(100):
            if self.call('list-panes', '-F', '#{pane_dead}') == '1':
                return
            time.sleep(.01)
        self.fail('Expected failed process to remain a dead pane')

    def test_failed_process_retries_same_pane(self):
        self.assertEqual(self.launch(['/usr/bin/false']), 'resume launched')
        self.wait_dead()
        pane = self.call('list-panes', '-F', '#{pane_id}')
        self.assertEqual(self.launch(['/usr/bin/sleep', '30']), 'resume retried')
        self.assertEqual(self.call('list-panes', '-F', '#{pane_id}'), pane)
        self.assertEqual(self.call('list-panes', '-F', '#{pane_dead}'), '0')

    def test_live_owned_pane_is_not_replaced(self):
        self.launch(['/usr/bin/sleep', '30'])
        pid = self.call('list-panes', '-F', '#{pane_pid}')
        self.assertEqual(self.launch(['/usr/bin/false']), 'existing live or unrelated pane; untouched')
        self.assertEqual(self.call('list-panes', '-F', '#{pane_pid}'), pid)

    def test_unrelated_shell_is_not_touched(self):
        self.call('new-session', '-d', '-s', self.row['name'], '/usr/bin/zsh -f')
        pid = self.call('list-panes', '-F', '#{pane_pid}')
        self.assertEqual(self.launch(['/usr/bin/false']), 'existing live or unrelated pane; untouched')
        self.assertEqual(self.call('list-panes', '-F', '#{pane_pid}'), pid)

    def test_live_writer_prevents_retry(self):
        self.launch(['/usr/bin/false'])
        self.wait_dead()
        with patch.object(restore, 'writer_lock_is_held', return_value=True):
            self.assertEqual(self.launch(['/usr/bin/sleep', '30']), 'already active; writer lock held')
        self.assertEqual(self.call('list-panes', '-F', '#{pane_dead}'), '1')

    def test_wrong_boot_dead_pane_is_not_retried(self):
        self.launch(['/usr/bin/false'])
        self.wait_dead()
        session = self.call('list-sessions', '-F', '#{session_id}')
        self.call('set-option', '-t', session, '@codex_restore_boot', 'other-boot')
        self.assertEqual(self.launch(['/usr/bin/sleep', '30']), 'existing live or unrelated pane; untouched')

    def test_normal_exit_is_not_retried(self):
        self.launch(['/usr/bin/true'])
        self.wait_dead()
        self.assertEqual(self.launch(['/usr/bin/sleep', '30']), 'existing live or unrelated pane; untouched')


if __name__ == '__main__':
    unittest.main()
