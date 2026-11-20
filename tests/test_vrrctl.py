#!/usr/bin/env python3
"""VRR transactions run against fixtures, never the live desktop."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('vrrctl', str(ROOT / 'dots/.local/bin/vrrctl'))
spec = importlib.util.spec_from_loader(loader.name, loader)
vrr = importlib.util.module_from_spec(spec)
loader.exec_module(vrr)


def monitor(name='DP-1', model='27G2G4'):
    return dict(name=name, description='AOC 27G2G4 serial' if name == 'DP-1' else 'ARZOPA serial',
                model=model, make='AOC', width=1920, height=1080, refreshRate=60.0,
                x=0 if name == 'DP-1' else 1920, y=0, scale=1, transform=0,
                currentFormat='XRGB8888', colorManagementPreset='srgb', sdrBrightness=1,
                sdrSaturation=1, vrr=False, hardwareDetails={'vrrCapable': True})


class Policies(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.patches = [patch.object(vrr, 'STATE', self.root / 'vrr.json'),
                        patch.object(vrr, 'GENERATED', self.root / 'vrr-policies.lua'),
                        patch.object(vrr, 'current', return_value=[monitor(), monitor('HDMI-A-1', 'ARZOPA')]),
                        patch.object(vrr, 'status', return_value={'monitors': []})]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def test_disconnected_output_does_not_write(self):
        with self.assertRaisesRegex(ValueError, 'disconnected'):
            vrr.set_policy('DP-9', 1)
        self.assertFalse(vrr.STATE.exists())

    def test_global_rejects_inherit(self):
        with self.assertRaises(ValueError):
            vrr.set_policy('global', -1)
        self.assertFalse(vrr.STATE.exists())

    def test_arzopa_policy_matches_its_canonical_restore_profile(self):
        with patch.object(vrr, 'apply'):
            vrr.set_policy('HDMI-A-1', 0)
        self.assertIn('HDMI-A-1', json.loads(vrr.STATE.read_text())['monitors'])

    def test_only_selected_monitor_changes(self):
        with patch.object(vrr, 'apply') as apply:
            vrr.set_policy('DP-1', 2)
        data = json.loads(vrr.STATE.read_text())
        entry = data['monitors']['desc:AOC 27G2G4 serial']
        self.assertEqual(entry['policy'], 2)
        self.assertEqual(entry['profile']['mode'], '1920x1080@60.000000')
        self.assertEqual(len(apply.call_args.args[1]), 1)
        self.assertEqual(apply.call_args.args[1][0]['name'], 'DP-1')

    def test_global_changes_only_inheriting_outputs(self):
        with patch.object(vrr, 'apply') as apply:
            vrr.set_policy('global', 0)
        self.assertEqual([m['name'] for m in apply.call_args.args[1]], ['DP-1'])

    def test_failed_apply_restores_exact_saved_bytes(self):
        vrr.save({'global': 0, 'monitors': {}})
        before = {p: p.read_bytes() for p in (vrr.STATE, vrr.GENERATED)}
        with patch.object(vrr, 'apply', side_effect=RuntimeError('IPC failed')):
            with self.assertRaisesRegex(RuntimeError, 'IPC failed'):
                vrr.set_policy('DP-1', 1)
        self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_soft_apply_restores_brightness_and_keeps_refresh_layout(self):
        commands = []
        m = monitor()
        m['sdrBrightness'] = .87
        with patch.object(vrr, 'evaluate', side_effect=commands.append), patch.object(vrr.time, 'sleep'):
            vrr.apply({'global': 2, 'monitors': {}}, [m])
        self.assertIn('0.87001', commands[0])
        self.assertIn('0.87', commands[1])
        for command in commands[:2]:
            self.assertIn('1920x1080@60.000000', command)
            self.assertIn('["position"]="0x0"', command)
        self.assertFalse(any('require("monitors")' in c for c in commands))

    def test_restore_runs_when_soft_apply_fails(self):
        commands = []
        def evaluate(command):
            commands.append(command)
            if len(commands) == 1:
                raise RuntimeError('IPC failed')
        with patch.object(vrr, 'evaluate', side_effect=evaluate):
            with self.assertRaises(RuntimeError):
                vrr.apply({'global': 0, 'monitors': {}}, [monitor()])
        self.assertEqual(len(commands), 2)
        self.assertIn('["sdrbrightness"]=1', commands[1])

    def test_arzopa_8bit_srgb_snapshot_disables_auto_hdr_and_wcg(self):
        arzopa = monitor('HDMI-A-1', 'ARZOPA')
        snap = vrr.snapshot(arzopa)
        self.assertEqual(snap['supports_hdr'], -1)
        self.assertEqual(snap['supports_wide_color'], -1)
        self.assertNotIn('supports_hdr', vrr.snapshot(monitor('DP-1', '27G2G4')))
        arzopa_10b = dict(arzopa, currentFormat='XRGB2101010')
        self.assertNotIn('supports_hdr', vrr.snapshot(arzopa_10b))


if __name__ == '__main__':
    unittest.main()
