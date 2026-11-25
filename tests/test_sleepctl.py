#!/usr/bin/env python3
"""Unit tests for dots/.local/bin/sleepctl."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SLEEPCTL = REPO / 'dots/.local/bin/sleepctl'


class SleepCtlTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.cfg = self.root / 'hypr'
        self.run = self.root / 'run'
        self.ps = self.root / 'power_supply'
        self.ps.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def set_power(self, ac_online: bool | None, battery_status: str | None = 'Full'):
        for child in self.ps.iterdir():
            for sub in child.iterdir():
                sub.unlink()
            child.rmdir()
        if ac_online is not None:
            ac = self.ps / 'ACAD'
            ac.mkdir()
            (ac / 'type').write_text('Mains\n')
            (ac / 'online').write_text('1\n' if ac_online else '0\n')
        if battery_status is not None:
            bat = self.ps / 'BAT1'
            bat.mkdir()
            (bat / 'type').write_text('Battery\n')
            (bat / 'status').write_text(battery_status + '\n')

    def call(self, *args):
        env = dict(os.environ)
        env.update({
            'SLEEPCTL_CONFIG_DIR': str(self.cfg),
            'SLEEPCTL_RUNTIME_DIR': str(self.run),
            'SLEEPCTL_POWER_SUPPLY_DIR': str(self.ps),
            'SLEEPCTL_NO_SYSTEM': '1',
        })
        res = subprocess.run([str(SLEEPCTL), *args], env=env, capture_output=True, text=True, check=True)
        return json.loads(res.stdout)

    def test_defaults_on_ac_never_sleep_and_inhibit_lid(self):
        self.set_power(ac_online=True, battery_status='Full')
        status = self.call('sync')
        self.assertFalse(status['keepAwake'])
        self.assertTrue(status['hasBattery'])
        self.assertTrue(status['onAc'])
        self.assertEqual(status['effectiveSleepMinutes'], 0)
        self.assertEqual(status['effectiveLidAction'], 'ignore')
        self.assertTrue(status['inhibitorActive'])
        self.assertEqual(status['inhibitorWhat'], 'idle:handle-lid-switch')
        conf = (self.cfg / 'hypridle.conf').read_text()
        self.assertNotIn('listener {', conf)

    def test_on_battery_generates_hypridle_listeners(self):
        self.set_power(ac_online=False, battery_status='Discharging')
        status = self.call('sync')
        self.assertFalse(status['onAc'])
        self.assertEqual(status['powerSource'], 'battery')
        self.assertEqual(status['effectiveSleepMinutes'], 15)
        self.assertEqual(status['effectiveLidAction'], 'suspend')
        self.assertFalse(status['inhibitorActive'])
        conf = (self.cfg / 'hypridle.conf').read_text()
        self.assertIn('timeout = 720', conf)
        self.assertIn('timeout = 780', conf)
        self.assertIn('timeout = 900', conf)
        self.assertIn('sleepctl action sleep', conf)

    def test_keep_awake_overrides_battery_sleep_and_lid(self):
        self.set_power(ac_online=False, battery_status='Discharging')
        status = self.call('set', '--keep-awake', 'on')
        self.assertTrue(status['keepAwake'])
        self.assertEqual(status['effectiveSleepMinutes'], 0)
        self.assertEqual(status['effectiveLidAction'], 'ignore')
        self.assertEqual(status['inhibitorWhat'], 'idle:sleep:handle-lid-switch')
        conf = (self.cfg / 'hypridle.conf').read_text()
        self.assertNotIn('listener {', conf)

    def test_custom_ac_and_battery_timeouts(self):
        self.set_power(ac_online=True, battery_status='Charging')
        status = self.call('set', '--ac', '30', '--battery', '10', '--lid-ac', 'suspend', '--lid-battery', 'ignore')
        self.assertEqual(status['acSleepMinutes'], 30)
        self.assertEqual(status['batterySleepMinutes'], 10)
        self.assertEqual(status['effectiveSleepMinutes'], 30)
        self.assertEqual(status['effectiveLidAction'], 'suspend')
        self.assertFalse(status['inhibitorActive'])
        conf = (self.cfg / 'hypridle.conf').read_text()
        self.assertIn('timeout = 1800', conf)

        # Unplug AC -> switches immediately to 10m + lid ignore
        self.set_power(ac_online=False, battery_status='Discharging')
        status2 = self.call('sync')
        self.assertEqual(status2['effectiveSleepMinutes'], 10)
        self.assertEqual(status2['effectiveLidAction'], 'ignore')
        self.assertEqual(status2['inhibitorWhat'], 'handle-lid-switch')
        conf2 = (self.cfg / 'hypridle.conf').read_text()
        self.assertIn('timeout = 600', conf2)

    def test_desktop_without_battery(self):
        self.set_power(ac_online=None, battery_status=None)
        # Peripheral batteries (mouse/controller) report scope=Device and must be ignored.
        mouse = self.ps / 'hidpp_battery_0'
        mouse.mkdir()
        (mouse / 'type').write_text('Battery\n')
        (mouse / 'scope').write_text('Device\n')
        (mouse / 'status').write_text('Discharging\n')
        status = self.call('sync')
        self.assertFalse(status['hasBattery'])
        self.assertTrue(status['onAc'])
        self.assertEqual(status['inhibitorWhat'], 'idle')
        status2 = self.call('toggle')
        self.assertTrue(status2['keepAwake'])
        self.assertEqual(status2['inhibitorWhat'], 'idle:sleep')


if __name__ == '__main__':
    unittest.main()
