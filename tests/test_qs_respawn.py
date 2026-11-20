#!/usr/bin/env python3
"""Check crash recovery with fake compositor discovery and shell processes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(os.environ.get('QS_RESPAWN_SCRIPT', Path(__file__).resolve().parents[1]
    / 'dots/.config/hypr/hyprland/scripts/qs_respawn.sh'))

SHIM = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
scenario = json.loads((root / 'scenario.json').read_text())
if name == 'hyprctl':
    assert sys.argv[1:] == ['instances', '-j'], sys.argv
    count = root / 'discovery-count'
    n = int(count.read_text()) if count.exists() else 0
    count.write_text(str(n + 1))
    snapshots = scenario['snapshots']
    print(json.dumps(snapshots[min(n, len(snapshots) - 1)]))
elif name == 'qs':
    output = root / 'launches.json'
    launches = json.loads(output.read_text()) if output.exists() else []
    n = len(launches)
    launches.append({'signature': os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'),
                     'display': os.environ.get('WAYLAND_DISPLAY'),
                     'args': sys.argv[1:]})
    output.write_text(json.dumps(launches))
    sys.exit(scenario.get('exits', [0])[min(n, len(scenario.get('exits', [0])) - 1)])
elif name in ('sleep', 'notify-send'):
    pass
else:
    raise AssertionError(name)
'''


def instance(signature, display='wayland-test'):
    return {'instance': signature, 'wl_socket': display, 'pid': 123, 'time': 1}


class RespawnTest(unittest.TestCase):
    def run_launcher(self, snapshots, exits=None, signature='dead', display='wayland-test'):
        with tempfile.TemporaryDirectory(prefix='qs-respawn-test-') as tmp:
            root = Path(tmp)
            bins = root / 'bin'
            bins.mkdir()
            for name in ('hyprctl', 'qs', 'sleep', 'notify-send'):
                shim = bins / name
                shim.write_text(SHIM)
                shim.chmod(0o755)
            scenario = {'snapshots': snapshots}
            if exits is not None:
                scenario['exits'] = exits
            (root / 'scenario.json').write_text(json.dumps(scenario))
            env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
                       FIXTURE=str(root), HOME=str(root), XDG_RUNTIME_DIR=str(root),
                       HYPRLAND_INSTANCE_SIGNATURE=signature, WAYLAND_DISPLAY=display)
            result = subprocess.run(['bash', str(SCRIPT), 'ii'], env=env,
                                    text=True, capture_output=True, timeout=15)
            output = root / 'launches.json'
            launches = json.loads(output.read_text()) if output.exists() else []
            count = root / 'discovery-count'
            return result, launches, int(count.read_text()) if count.exists() else 0

    def test_stale_signature_replaced_on_same_display(self):
        result, launches, _ = self.run_launcher([[instance('new'), instance('nested', 'wayland-other')]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(launches[0]['signature'], 'new')
        self.assertEqual(launches[0]['display'], 'wayland-test')
        self.assertEqual(launches[0]['args'], ['--no-duplicate', '-c', 'ii'])

    def test_compositor_changes_between_crashes(self):
        result, launches, _ = self.run_launcher([[instance('old')], [instance('new')]],
                                                exits=[1, 0], signature='old')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([x['signature'] for x in launches], ['old', 'new'])

    def test_waits_for_watchdog_restart(self):
        result, launches, count = self.run_launcher([[], [instance('new')]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count, 2)
        self.assertEqual(launches[0]['signature'], 'new')

    def test_clean_exit_stops_supervisor(self):
        result, launches, count = self.run_launcher([[instance('old')]], signature='old')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(launches), 1)
        self.assertEqual(count, 1)

    def test_never_switches_to_another_display(self):
        result, launches, count = self.run_launcher([[instance('nested', 'wayland-other')]])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(launches, [])
        self.assertEqual(count, 15)

    def test_absent_compositor_exits_after_bounded_wait(self):
        result, launches, count = self.run_launcher([[]])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(launches, [])
        self.assertEqual(count, 15)

    def test_ambiguous_display_is_not_chosen_arbitrarily(self):
        result, launches, _ = self.run_launcher([[instance('first'), instance('second')]])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(launches, [])

    def test_absolute_wayland_socket(self):
        result, launches, _ = self.run_launcher([[instance('new')]],
                                                display='/run/user/1000/wayland-test')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(launches[0]['signature'], 'new')

    def test_prefers_user_local_wrapper_over_system_qs_only(self):
        with tempfile.TemporaryDirectory(prefix='qs-respawn-bin-') as tmp:
            root = Path(tmp)
            local_qs = root / '.local/bin/qs'
            local_qs.parent.mkdir(parents=True)
            local_qs.write_text('#!/bin/sh\nexit 0\n')
            local_qs.chmod(0o755)
            path_qs = root / 'bin/qs'
            path_qs.parent.mkdir(parents=True)
            path_qs.write_text('#!/bin/sh\nexit 0\n')
            path_qs.chmod(0o755)
            body = SCRIPT.read_text()
            fn_def = body[body.index('resolve_qs_bin()'):body.index('\nwhile true; do')]
            system_env = dict(os.environ, HOME=str(root), PATH='/usr/bin:/bin')
            res_sys = subprocess.run(['bash', '-c', fn_def + '\nresolve_qs_bin'],
                                     env=system_env, text=True, capture_output=True, check=True)
            self.assertEqual(res_sys.stdout.strip(), str(local_qs))
            override_env = dict(os.environ, HOME=str(root), PATH=f'{path_qs.parent}:/usr/bin:/bin')
            res_ovr = subprocess.run(['bash', '-c', fn_def + '\nresolve_qs_bin'],
                                     env=override_env, text=True, capture_output=True, check=True)
            self.assertEqual(res_ovr.stdout.strip(), str(path_qs))


if __name__ == '__main__':
    unittest.main()
