#!/usr/bin/env python3
"""Sunshine display ownership regression tests; never contact the compositor."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMAND = Path(os.environ.get('SUNSHINE_DISPLAY_UNDER_TEST',
                              ROOT / 'dots/.local/bin/sunshine-display'))

FAKE = r'''#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
p = Path(os.environ['SUNSHINE_TEST_STATE'])
s = json.loads(p.read_text())
tool, args = Path(sys.argv[0]).name, sys.argv[1:]
s['calls'].append([tool, args])
result, status = 'ok', 0
if tool == 'refresh-displays':
    status = int(os.environ.get('SUNSHINE_TEST_FAIL_RESTORE', '0'))
    if args[0] == 'wake':
        for m in s['monitors']:
            m['refreshRate'], m['dpmsStatus'] = 144, True
elif args[:1] == ['instances']:
    result = json.dumps(s.get('instances', [{'instance': 'test-session', 'wl_socket': 'wayland-test'}]))
elif args[:1] == ['monitors']:
    result = json.dumps(s['monitors'] if 'all' in args else
                        [m for m in s['monitors'] if not m['disabled']])
elif args[:1] == ['devices']:
    result = '{"keyboards": []}'
elif args[:1] == ['eval']:
    code = args[1]
    if 'hl.dsp.dpms' in code:
        name = re.search(r"monitor = '([^']+)'", code).group(1)
        for m in s['monitors']:
            if m['name'] == name: m['dpmsStatus'] = True
    elif 'hl.monitor' in code:
        s['mutation_markers'].append(
            (p.parent / 'run/sunshine-display.pending').exists())
        if 'clone_enabled' in code:
            for m in s['monitors']:
                if m['name'] != 'SUNSHINE':
                    m['disabled'], m['refreshRate'] = False, 144.0
        else:
            output = re.search(r"output = '([^']+)'", code).group(1)
            name = 'DP-1' if output.startswith('desc:AOC') else output
            for m in s['monitors']:
                if m['name'] == name:
                    m['disabled'] = 'disabled = true' in code
                    hz = re.search(r"mode = '[^']+@([0-9.]+)'", code)
                    if hz: m['refreshRate'] = float(hz.group(1))
            status = int(os.environ.get('SUNSHINE_TEST_FAIL_PREPARE', '0'))
            if os.environ.get('SUNSHINE_TEST_LUA_ERROR'):
                result = 'Lua evaluation failed: rejected monitor rule'
elif args[:2] == ['output', 'create']:
    s['monitors'].append(dict(name=args[-1], disabled=False, refreshRate=60,
                             focused=False, dpmsStatus=True, activeWorkspace={'id': 1}))
elif args[:2] == ['output', 'remove']:
    s['monitors'] = [m for m in s['monitors'] if m['name'] != args[-1]]
else:
    raise RuntimeError('Unexpected fake call: ' + repr([tool, args]))
p.write_text(json.dumps(s))
print(result)
sys.exit(status)
'''


class SunshineDisplay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sunshine-display-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / 'run'
        (self.runtime / 'hypr/test-session').mkdir(parents=True)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ['hyprctl', 'refresh-displays']:
            script = self.bin / name
            script.write_text(FAKE)
            script.chmod(0o755)
        self.command = self.root / 'sunshine-display'
        # Redirect the fixed helper path, leaving the production control flow intact.
        self.command.write_text(COMMAND.read_text().replace(
            '$HOME/.local/bin/refresh-displays', str(self.bin / 'refresh-displays')))
        self.command.chmod(0o755)
        self.state = self.root / 'state.json'
        self.state.write_text(json.dumps({'calls': [], 'mutation_markers': [], 'monitors': [
            dict(name=name, disabled=False, refreshRate=144, focused=index == 0,
                 dpmsStatus=True, activeWorkspace={'id': index + 1})
            for index, name in enumerate(['DP-1', 'HDMI-A-1'])]}))
        self.marker = self.runtime / 'sunshine-display.pending'
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime),
                        HYPRLAND_INSTANCE_SIGNATURE='test-session',
                        WAYLAND_DISPLAY='wayland-test',
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        SUNSHINE_TEST_STATE=str(self.state))

    def call(self, *args, env=None, ok=True):
        result = subprocess.run([str(self.command), *args], env=env or self.env,
                                capture_output=True, text=True, timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def data(self):
        return json.loads(self.state.read_text())

    def test_idle_restore_never_contacts_display(self):
        env = dict(self.env, HYPRLAND_INSTANCE_SIGNATURE='')
        (self.runtime / 'hypr/test-session').rmdir()
        self.call('restore', env=env)
        self.assertEqual(self.data()['calls'], [])
        self.assertFalse(self.marker.exists())

    def test_prepare_then_undo_then_stop_restores_only_once(self):
        for target in ['aoc', 'arzopa', 'virtual', 'auto']:
            with self.subTest(target=target):
                before = len([c for c in self.data()['calls'] if c[0] == 'refresh-displays'])
                self.call('prepare', target, '120')
                self.assertEqual(self.marker.read_text().strip(), 'test-session')
                self.assertTrue(all(self.data()['mutation_markers']))
                self.call('restore')
                self.assertFalse(self.marker.exists())
                restored = self.data()
                self.assertEqual(len([c for c in restored['calls'] if c[0] == 'refresh-displays']), before + 1)
                self.assertEqual([m['name'] for m in restored['monitors']], ['DP-1', 'HDMI-A-1'])
                self.assertTrue(all(not m['disabled'] and m['refreshRate'] == 144 for m in restored['monitors']))
                self.call('restore')
                self.assertEqual(self.data(), restored)

    def test_prepare_arzopa_disables_hdr_and_wide_color_for_8bit_srgb(self):
        self.call('prepare', 'arzopa', '120')
        evals = [args[1] for tool, args in self.data()['calls'] if tool == 'hyprctl' and args[:1] == ['eval']]
        arzopa_apply = next(c for c in evals if "output = 'HDMI-A-1'" in c and 'disabled = false' in c)
        self.assertIn('supports_hdr = -1', arzopa_apply)
        self.assertIn('supports_wide_color = -1', arzopa_apply)

    def test_failed_prepare_rolls_back_immediately(self):
        self.call('prepare', 'aoc', env=dict(self.env, SUNSHINE_TEST_FAIL_PREPARE='1'), ok=False)
        self.assertFalse(self.marker.exists())
        self.assertTrue(all(self.data()['mutation_markers']))
        self.assertTrue(all(not m['disabled'] and m['refreshRate'] == 144 for m in self.data()['monitors']))

    def test_failed_rollback_retains_recovery_ownership(self):
        self.call('prepare', 'aoc', env=dict(self.env, SUNSHINE_TEST_FAIL_PREPARE='1',
                                            SUNSHINE_TEST_FAIL_RESTORE='1'), ok=False)
        self.assertTrue(self.marker.exists())
        self.call('restore')
        self.assertFalse(self.marker.exists())

    def test_zero_exit_lua_error_is_not_success(self):
        result = self.call('prepare', 'aoc', env=dict(self.env, SUNSHINE_TEST_LUA_ERROR='1'), ok=False)
        self.assertIn('rejected', result.stderr)
        self.assertFalse(self.marker.exists())

    def test_waking_display_preserves_stream_refresh(self):
        data = self.data()
        data['monitors'][0]['dpmsStatus'] = False
        self.state.write_text(json.dumps(data))
        self.call('prepare', 'aoc', '120')
        monitor = self.data()['monitors'][0]
        self.assertTrue(monitor['dpmsStatus'])
        self.assertEqual(monitor['refreshRate'], 120)
        self.assertFalse(any(c[0] == 'refresh-displays' for c in self.data()['calls']))

    def test_no_physical_output_keeps_virtual_and_recovery_state(self):
        self.call('prepare', 'virtual')
        data = self.data()
        data['monitors'] = [m for m in data['monitors'] if m['name'] == 'SUNSHINE']
        self.state.write_text(json.dumps(data))
        self.call('restore', ok=False)
        self.assertTrue(self.marker.exists())
        self.assertEqual([m['name'] for m in self.data()['monitors']], ['SUNSHINE'])

    def test_ambiguous_compositor_makes_no_change(self):
        data = self.data()
        data['instances'] = [{'instance': 'a', 'wl_socket': 'wayland-a'},
                             {'instance': 'b', 'wl_socket': 'wayland-b'}]
        self.state.write_text(json.dumps(data))
        self.call('prepare', 'aoc', ok=False)
        self.assertEqual(self.data()['calls'], [['hyprctl', ['instances', '-j']]])
        self.assertFalse(self.marker.exists())

    def test_common_display_lock_prevents_conflicting_changes(self):
        with (self.runtime / 'refresh-displays.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.call('prepare', 'aoc', ok=False)
        self.assertEqual(self.data()['calls'], [['hyprctl', ['instances', '-j']]])
        self.assertFalse(self.marker.exists())

    def test_failed_restore_can_retry(self):
        self.call('prepare', 'aoc')
        self.call('restore', env=dict(self.env, SUNSHINE_TEST_FAIL_RESTORE='1'), ok=False)
        self.assertTrue(self.marker.exists())
        self.call('restore')
        self.assertFalse(self.marker.exists())

    def test_previous_compositor_state_does_not_change_current_desktop(self):
        self.marker.write_text('previous-session\n')
        self.call('restore')
        self.assertEqual(self.data()['calls'], [['hyprctl', ['instances', '-j']]])
        self.assertFalse(self.marker.exists())

    def test_force_retains_manual_recovery(self):
        self.call('restore', '--force')
        self.assertTrue(any(c[0] == 'refresh-displays' for c in self.data()['calls']))
        self.assertFalse(self.marker.exists())

    def test_invalid_target_makes_no_change(self):
        self.call('prepare', 'not-a-target', ok=False)
        self.assertEqual(self.data()['calls'], [])
        self.assertFalse(self.marker.exists())

    def test_existing_lock_is_respected(self):
        with (self.runtime / 'sunshine-display.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen([str(self.command), 'restore'], env=self.env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.communicate(timeout=0.1)
                self.assertEqual(self.data()['calls'], [])
                fcntl.flock(lock, fcntl.LOCK_UN)
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, stderr + stdout)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main()
