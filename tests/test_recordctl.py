#!/usr/bin/env python3
"""Unit tests for dots/.local/bin/recordctl."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
RECORDCTL = REPO / 'dots/.local/bin/recordctl'


def load_module():
    loader = importlib.machinery.SourceFileLoader('recordctl_mod', str(RECORDCTL))
    spec = importlib.util.spec_from_loader('recordctl_mod', loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class RecordCtlTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.cfg = self.root / 'hypr'
        self.run = self.root / 'run'
        self.ps = self.root / 'power_supply'
        self.ps.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *args):
        env = dict(os.environ)
        env.update({
            'RECORDCTL_CONFIG_DIR': str(self.cfg),
            'RECORDCTL_RUNTIME_DIR': str(self.run),
            'RECORDCTL_POWER_SUPPLY_DIR': str(self.ps),
            'RECORDCTL_NO_NOTIFY': '1',
        })
        res = subprocess.run([str(RECORDCTL), *args], env=env, capture_output=True, text=True, check=True)
        return json.loads(res.stdout)

    def test_default_preset_laptop_vs_desktop(self):
        # Desktop (no battery) -> balanced
        status = self.call('status')
        self.assertEqual(status['preset'], 'balanced')
        self.assertEqual(status['backend'], 'gsr')
        self.assertEqual(status['codec'], 'hevc')

        # Laptop (system battery) -> gaming (lowest FPS impact)
        bat = self.ps / 'BAT1'
        bat.mkdir()
        (bat / 'type').write_text('Battery\n')
        status_lap = self.call('status')
        self.assertEqual(status_lap['preset'], 'gaming')
        self.assertTrue(status_lap['lowPower'])
        self.assertEqual(status_lap['tune'], 'performance')

    def test_presets_and_custom_mutation(self):
        st = self.call('preset', 'quality')
        self.assertEqual(st['preset'], 'quality')
        self.assertEqual(st['codec'], 'hevc_10bit')
        self.assertEqual(st['audioCodec'], 'flac')
        self.assertEqual(st['container'], 'mkv')

        st2 = self.call('set', '--fps', '120', '--audio', 'system_mic', '--low-power', 'on')
        self.assertEqual(st2['preset'], 'custom')
        self.assertEqual(st2['fps'], 120)
        self.assertEqual(st2['audioMode'], 'system_mic')
        self.assertTrue(st2['lowPower'])

    def test_slurp_to_gsr_region_and_command_builder(self):
        mod = load_module()
        self.assertEqual(mod.slurp_to_gsr_region('100,200 1280x720'), '1280x720+100+200')
        self.assertEqual(mod.slurp_to_gsr_region('640x480+10+20'), '640x480+10+20')

        settings = dict(mod.PRESETS['gaming'], audioMode='system_mic', showCursor=True)
        hw = {'hasGsr': True, 'hasKms': True, 'hasWfRecorder': True,
              'vaapiCodecs': ['h264', 'hevc', 'hevc_10bit'], 'renderDevice': '/dev/dri/renderD128'}
        cmd, backend = mod.build_command(settings, Path('/tmp/out.mp4'), 'eDP-1', 60, '10,20 800x600', 'system_mic', hw)
        self.assertEqual(backend, 'gsr')
        self.assertIn('gpu-screen-recorder', cmd[0])
        self.assertIn('region', cmd)
        self.assertIn('800x600+10+20', cmd)
        self.assertIn('default_output|default_input', cmd)
        self.assertIn('-low-power', cmd)
        self.assertEqual(cmd[cmd.index('-low-power') + 1], 'yes')

        # Fallback to wf-recorder VAAPI when backend=wf-vaapi
        settings['backend'] = 'wf-vaapi'
        cmd2, backend2 = mod.build_command(settings, Path('/tmp/out.mp4'), 'DP-1', 144, None, 'system', hw)
        self.assertEqual(backend2, 'wf-vaapi')
        self.assertEqual(cmd2[0], 'wf-recorder')
        self.assertIn('hevc_vaapi', cmd2)
        self.assertIn('/dev/dri/renderD128', cmd2)


if __name__ == '__main__':
    unittest.main()
