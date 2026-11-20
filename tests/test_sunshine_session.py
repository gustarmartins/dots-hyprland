#!/usr/bin/env python3
"""Test on-demand lifecycle with private fake processes, no Sunshine or displays."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / 'dots/.local/bin/sunshine-session'
loader = importlib.machinery.SourceFileLoader('sunshine_session_test_module', str(COMMAND))
spec = importlib.util.spec_from_loader(loader.name, loader)
session = importlib.util.module_from_spec(spec)
loader.exec_module(session)

FAKE = '''import os, signal, subprocess, sys, time
from pathlib import Path
mode, folder = sys.argv[1], Path(sys.argv[2])
def log(message): print('[2026-11-17 23:00:00.000]: Info: ' + message, flush=True)
log('Sunshine version: fake-test')
if mode == 'quit': sys.exit(0)
if mode == 'failure': sys.exit(7)
if mode == 'detached':
    child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
    (folder / 'detached.pid').write_text(str(child.pid))
    sys.exit(0)
log('CLIENT CONNECTED')
(folder / 'connected').write_text('ready')
if mode == 'disconnect': log('CLIENT DISCONNECTED')
if mode == 'timeout': log('192.0.2.1: Ping Timeout')
while True: time.sleep(1)
'''


class OnDemand(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sunshine-session-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.record = self.root / 'child.json'
        self.fake = self.root / 'fake.py'
        self.fake.write_text(FAKE)
        self.runner = self.root / 'runner.py'
        self.runner.write_text(
            'import importlib.machinery, importlib.util, pathlib, sys\n'
            f'loader=importlib.machinery.SourceFileLoader("worker", {str(COMMAND)!r})\n'
            'spec=importlib.util.spec_from_loader(loader.name, loader)\n'
            'worker=importlib.util.module_from_spec(spec); loader.exec_module(worker)\n'
            f'raise SystemExit(worker.supervise([sys.executable, {str(self.fake)!r}, sys.argv[1], '
            f'{str(self.root)!r}], record=pathlib.Path({str(self.record)!r})))\n')

    def launch(self, mode):
        process = subprocess.Popen([sys.executable, str(self.runner), mode],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)
            session.cleanup_child(self.record)
        self.addCleanup(cleanup)
        return process

    def finish(self, process, expected=0):
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, expected, stdout + stderr)
        self.assertFalse(self.record.exists())
        return stdout, stderr

    def test_disconnect_stops_owned_process(self):
        _, stderr = self.finish(self.launch('disconnect'))
        self.assertIn('last client disconnected', stderr)

    def test_network_timeout_stops_owned_process(self):
        _, stderr = self.finish(self.launch('timeout'))
        self.assertIn('last client disconnected', stderr)

    def test_tray_exit_finishes_without_restart(self):
        self.finish(self.launch('quit'))

    def test_failure_is_reported_without_restart(self):
        self.finish(self.launch('failure'), expected=7)

    def test_manual_stop_is_forwarded(self):
        process = self.launch('idle')
        deadline = time.monotonic() + 3
        while not (self.root / 'connected').exists() and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue((self.root / 'connected').exists())
        self.assertIsNone(process.poll())
        process.terminate()
        self.finish(process)

    def test_detached_application_does_not_keep_service_alive_or_get_killed(self):
        process = self.launch('detached')
        self.finish(process)
        pid = int((self.root / 'detached.pid').read_text())
        try:
            os.kill(pid, 0)
        finally:
            os.kill(pid, signal.SIGTERM)

    def test_only_last_client_disconnect_stops(self):
        tracker = session.StreamEvents()
        def feed(message): return tracker.feed('[2026-11-17 23:00:00.000]: Info: ' + message)
        self.assertIsNone(feed('CLIENT CONNECTED'))
        self.assertIsNone(feed('CLIENT CONNECTED'))
        self.assertIsNone(feed('CLIENT DISCONNECTED'))
        self.assertEqual(tracker.connected, 1)
        self.assertEqual(feed('CLIENT DISCONNECTED'), 'last client disconnected')

    def test_embedded_log_text_is_not_a_disconnect(self):
        tracker = session.StreamEvents()
        self.assertIsNone(tracker.feed('input payload CLIENT DISCONNECTED'))
        self.assertIsNone(tracker.feed('[time]: Debug: CLIENT DISCONNECTED'))

    def test_cleanup_does_not_signal_reused_pid(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        try:
            saved = session.identity(child.pid)
            saved['start'] = str(int(saved['start']) + 1)
            session.save_child(self.record, saved)
            session.cleanup_child(self.record)
            self.assertIsNone(child.poll())
            self.assertFalse(self.record.exists())
        finally:
            child.terminate()
            child.wait(timeout=3)

    def test_cleanup_stops_verified_orphan(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        try:
            session.save_child(self.record, session.identity(child.pid))
            session.cleanup_child(self.record)
            child.wait(timeout=3)
            self.assertFalse(self.record.exists())
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=3)


if __name__ == '__main__':
    unittest.main()
