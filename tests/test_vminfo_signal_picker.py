#!/usr/bin/env python3
"""Exercise the manager's real X handler and pidfd signalling on disposable children."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(__file__).resolve().parents[1] / 'dots/.local/bin/vminfo'


class SignalPicker(unittest.TestCase):
    def test_x_remembers_the_signal_and_needs_one_confirmation(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, XDG_STATE_HOME=home):
            lib = runpy.run_path(str(SOURCE))
            send = lib['run_signal_action']
            scope = send.__globals__
            manager = lib['ProcessManager']()
            term = Mock()
            def press_x(child, choice, expected):
                pid = str(child.pid)
                identity = lib['read_process_identity'](pid)
                row = {'pid':pid, 'comm':'sleep', 'rss':4096, 'swap':0, 'uid':os.getuid()}
                manager.enter([row], False)
                manager.selected.add(pid)
                manager.identities[pid] = identity
                with patch.dict(scope, keyboard_input=Mock(return_value=choice), get_enriched_processes=lambda: []), contextlib.redirect_stdout(io.StringIO()):
                    manager.handle_key('x',term,0,0,10)
                    scope['keyboard_input'].assert_called_once()
                    self.assertIn('Signal [' + expected + ']', scope['keyboard_input'].call_args.args[0])
                self.assertFalse(manager.selected)
            for choice,default,expected in [('STOP','TERM','STOP'),('CONT','STOP','CONT'),('KILL','CONT','KILL'),('','KILL','KILL')]:
                child = subprocess.Popen(['/usr/bin/sleep','30'])
                try:
                    press_x(child,choice,default)
                    self.assertEqual(manager.notice, 'SIG' + expected + ' sent to 1 selected.')
                    if expected == 'KILL':
                        self.assertEqual(child.wait(3), -signal.SIGKILL)
                    if expected == 'STOP':
                        _, status = os.waitpid(child.pid, os.WUNTRACED)
                        self.assertTrue(os.WIFSTOPPED(status))
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.wait(3)
            self.assertEqual(runpy.run_path(str(SOURCE))['preferred_signal'](),'KILL')


if __name__ == '__main__':
    unittest.main()
