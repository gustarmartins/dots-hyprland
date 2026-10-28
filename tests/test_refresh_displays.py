#!/usr/bin/env python3
"""Exercise display power recovery with fake IPC, input, sysfs and virtual time.

Never connects to the real compositor or blanks a physical display.
"""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / 'dots/.local/bin/refresh-displays'

FAKE = r'''#!/usr/bin/env python3
import json, os, re, signal, sys
from pathlib import Path
p = Path(os.environ['DISPLAY_TEST_STATE'])
s = json.loads(p.read_text())
tool, args = Path(sys.argv[0]).name, sys.argv[1:]
s['events'].append([s['time'], tool, args])
result = 'ok'
terminate = False
if tool == 'sleep':
    s['time'] += float(args[0])
    off = [m for m in s['monitors'] if not m['dpmsStatus']]
    if off and not s.get('input_sent'):
        s['input_sent'] = True
        # Enter release / mouse motion wakes outputs if either policy allows it.
        if any(s['options'].values()):
            for m in s['monitors']: m['dpmsStatus'] = True
    if off and s.get('fault') == 'early_wake' and s['time'] >= 2:
        for m in off: m['dpmsStatus'] = True
    if off and s.get('fault') == 'disconnect':
        s['monitors'] = [m for m in s['monitors'] if m['name'] != 'DP-1']
    if off and s.get('fault') == 'signal' and not s.get('signal_sent'):
        s['signal_sent'] = True
        terminate = True
    if off and s.get('fault') == 'wake_after_guard' and any(s['options'].values()):
        for m in off: m['dpmsStatus'] = True
elif tool == 'hyprsunsetctl':
    if args[0] == 'identity': s['color']['identity'] = args[1]
    else: s['color'][args[0]] = args[1]
elif tool == 'hyprctl':
    if args[0] == 'monitors': result = json.dumps(s['monitors'])
    elif args[:2] == ['-j', 'getoption']:
        result = json.dumps({'bool': s['options'][args[2].split(':')[1]]})
    elif args[0] == 'hyprsunset': result = s['color'][args[1]]
    elif args[0] == 'eval':
        code = args[1]
        if 'hl.config' in code:
            for key, value in re.findall(r'(mouse_move_enables_dpms|key_press_enables_dpms)\s*=\s*(true|false)', code):
                s['options'][key] = value == 'true'
        elif 'hl.dsp.dpms' in code:
            action = re.search(r'action\s*=\s*"(\w+)"', code).group(1)
            selector = re.search(r'monitor\s*=\s*"([^"]+)"', code)
            selected = selector.group(1) if selector else ''
            if s.get('fault') == 'disconnect_at_dispatch' and action == 'off':
                s['monitors'] = [m for m in s['monitors'] if m['name'] != selected]
            targets = [m for m in s['monitors'] if not selected or m['name'] == selected]
            # Model Hyprland's dangerous unknown-selector fallback.
            missing_guarded = not targets and 'assert(hl.get_monitor' in code
            if not targets and not missing_guarded: targets = s['monitors']
            if missing_guarded: result = 'Output disconnected'
            elif s.get('fault') == 'reject_off' and action == 'off': result = 'rejected'
            else:
                for m in targets: m['dpmsStatus'] = action == 'on'
        elif 'hl.monitor' in code:
            selector = re.search(r'output\s*=\s*"([^"]+)"', code)
            if not selector: raise RuntimeError('missing profile output')
            s['applied'].append(selector.group(1))
        elif 'require("monitors")' in code:
            s['applied'].extend(['DP-1', 'HDMI-A-1'])
        else: raise RuntimeError('unexpected eval: ' + code)
    else: raise RuntimeError('unexpected IPC: ' + repr(args))
else: raise RuntimeError(tool)
for name in ['DP-1', 'HDMI-A-1']:
    root = p.parent / 'drm' / ('card1-' + name)
    matches = [m for m in s['monitors'] if m['name'] == name]
    root.mkdir(exist_ok=True, parents=True)
    (root / 'status').write_text('connected' if matches else 'disconnected')
    awake = not matches or matches[0]['dpmsStatus'] or s.get('fault') == 'kernel_stuck_on'
    (root / 'dpms').write_text('On' if awake else 'Off')
p.write_text(json.dumps(s))
if terminate: os.kill(os.getppid(), signal.SIGTERM)
if tool != 'sleep': print(result)
'''


class DisplayRecovery(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='display-recovery-test-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        bindir = self.home / '.local/bin'
        bindir.mkdir(parents=True)
        runtime = self.home / 'run'
        runtime.mkdir()
        config = self.home / '.config/hypr'
        config.mkdir(parents=True)
        shutil.copy2(ROOT / 'dots/.config/hypr/monitors.lua', config / 'monitors.lua')
        self.command = bindir / 'refresh-displays'
        # Redirect only the sysfs boundary; all production shell/Lua logic runs.
        self.command.write_text(COMMAND.read_text().replace('/sys/class/drm', str(self.home / 'drm')))
        self.command.chmod(0o755)
        fake = bindir / 'fake'
        fake.write_text(FAKE)
        fake.chmod(0o755)
        for name in ['hyprctl', 'hyprsunsetctl', 'sleep']:
            (bindir / name).symlink_to(fake)
        self.statefile = self.home / 'state.json'
        monitors = []
        for name, x, y, vrr in [('DP-1', 0, 0, True), ('HDMI-A-1', 1920, 500, False)]:
            monitors.append(dict(name=name, width=1920, height=1080, refreshRate=144.001,
                                 x=x, y=y, scale=1, transform=0, colorManagementPreset='srgb',
                                 currentFormat='XRGB8888', disabled=False, dpmsStatus=True, vrr=vrr))
        self.statefile.write_text(json.dumps(dict(
            monitors=monitors, time=0, events=[], applied=[],
            options=dict(mouse_move_enables_dpms=True, key_press_enables_dpms=True),
            color=dict(identity='false', temperature='4800', gamma='83'))))
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(runtime),
                        DISPLAY_TEST_STATE=str(self.statefile), PATH=str(bindir) + ':' + os.environ['PATH'])

    def state(self):
        return json.loads(self.statefile.read_text())

    def update(self, **changes):
        state = self.state()
        state.update(changes)
        self.statefile.write_text(json.dumps(state))

    def run_command(self, *args, expected=0):
        result = subprocess.run([str(self.command), *args], env=self.env, text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def assert_restored(self):
        state = self.state()
        self.assertTrue(all(m['dpmsStatus'] for m in state['monitors']))
        self.assertTrue(all(state['options'].values()))
        self.assertEqual(state['color'], dict(identity='false', temperature='4800', gamma='83'))

    def test_cycle_holds_off_despite_input_and_only_applies_target(self):
        self.run_command('cycle', 'DP-1')
        state = self.state()
        transitions = [(t, a[1]) for t, tool, a in state['events']
                       if tool == 'hyprctl' and a[0] == 'eval' and 'hl.dsp.dpms' in a[1]]
        self.assertEqual(len(transitions), 2)
        self.assertGreaterEqual(transitions[1][0] - transitions[0][0], 5)
        self.assertTrue(all('monitor = "DP-1"' in code for _, code in transitions))
        self.assertEqual(state['applied'], ['DP-1'])
        self.assert_restored()

    def test_sleep_stays_off_and_wake_is_idempotent(self):
        self.run_command('sleep')
        self.assertFalse(any(m['dpmsStatus'] for m in self.state()['monitors']))
        self.assertTrue(all(self.state()['options'].values()))
        self.run_command('wake')
        self.run_command('wake')
        self.assert_restored()

    def test_target_sleep_preserves_peer_and_previous_input_policy(self):
        policy = dict(mouse_move_enables_dpms=False, key_press_enables_dpms=True)
        self.update(options=policy)
        self.run_command('sleep', 'DP-1')
        state = self.state()
        self.assertFalse(state['monitors'][0]['dpmsStatus'])
        self.assertTrue(state['monitors'][1]['dpmsStatus'])
        self.assertEqual(state['options'], policy)
        self.run_command('wake', 'DP-1')
        self.assertEqual(self.state()['applied'], ['DP-1'])

    def test_early_wake_fails_and_restores_settings(self):
        self.update(fault='early_wake')
        result = self.run_command('cycle', 'DP-1', expected=1)
        self.assertIn('did not stay off', result.stderr)
        self.assert_restored()

    def test_kernel_failure_is_not_reported_as_success(self):
        self.update(fault='kernel_stuck_on')
        result = self.run_command('sleep', 'DP-1', expected=1)
        self.assertIn('Timed out', result.stderr)
        self.assertNotIn('DPMS off verified', result.stdout)
        self.assert_restored()

    def test_sleep_detects_wake_after_input_policy_restored(self):
        self.update(fault='wake_after_guard')
        result = self.run_command('sleep', expected=1)
        self.assertIn('sleep did not persist', result.stderr)
        self.assert_restored()

    def test_signal_wakes_output_and_restores_input(self):
        self.update(fault='signal')
        self.run_command('cycle', 'DP-1', expected=143)
        self.assert_restored()

    def test_disconnect_does_not_wake_an_intentionally_sleeping_peer(self):
        monitors = self.state()['monitors']
        monitors[1]['dpmsStatus'] = False
        self.update(monitors=monitors, fault='disconnect')
        self.run_command('cycle', 'DP-1', expected=1)
        state = self.state()
        self.assertEqual(len(state['monitors']), 1)
        self.assertFalse(state['monitors'][0]['dpmsStatus'])
        self.assertTrue(all(state['options'].values()))
        self.assertFalse(any('action = "on"' in str(a) for _, _, a in state['events']))

    def test_rejected_off_restores_input(self):
        self.update(fault='reject_off')
        self.run_command('cycle', 'DP-1', expected=1)
        self.assert_restored()

    def test_disconnect_between_lookup_and_dispatch_never_powers_off_peer(self):
        self.update(fault='disconnect_at_dispatch')
        result = self.run_command('cycle', 'DP-1', expected=1)
        self.assertIn('Output disconnected', result.stderr)
        state = self.state()
        self.assertEqual(len(state['monitors']), 1)
        self.assertTrue(state['monitors'][0]['dpmsStatus'])
        self.assertTrue(all(state['options'].values()))

    def test_no_output_sleep_and_wake_fail(self):
        self.update(monitors=[])
        self.run_command('sleep', expected=1)
        self.run_command('wake', expected=1)
        self.run_command('wake', 'DP-1', expected=1)

    def test_status_is_read_only_and_available_during_refresh(self):
        with (self.home / 'run/refresh-displays.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_command('status')
            self.run_command('verify')
            self.run_command('cycle', expected=1)
        self.assertFalse(any(a[0] == 'eval' for _, tool, a in self.state()['events'] if tool == 'hyprctl'))

    def test_default_cycle_preserves_already_sleeping_outputs(self):
        monitors = self.state()['monitors']
        monitors[1]['dpmsStatus'] = False
        self.update(monitors=monitors)
        self.run_command()
        state = self.state()
        self.assertTrue(state['monitors'][0]['dpmsStatus'])
        self.assertFalse(state['monitors'][1]['dpmsStatus'])
        self.assertEqual(state['applied'], ['DP-1'])


if __name__ == '__main__':
    unittest.main()
