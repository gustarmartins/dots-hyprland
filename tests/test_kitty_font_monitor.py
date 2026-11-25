#!/usr/bin/env python3
"""Isolated unit tests for kitty-font-monitor, fontctl Kitty override, and Lua hook."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'dots/.local/bin/kitty-font-monitor'
FONTCTL = ROOT / 'dots/.local/bin/fontctl'
LUA_HOOK = ROOT / 'dots/.config/hypr/custom/kitty-monitor-font.lua'


def load_module():
    loader = importlib.machinery.SourceFileLoader('kitty_font_monitor', str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class KittyFontMonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kitty-font-monitor-test-')
        self.home = Path(self.tmp.name)
        self.config = self.home / '.config'
        self.config.mkdir(parents=True)
        kitty_dir = self.config / 'kitty'
        kitty_dir.mkdir(parents=True)
        (kitty_dir / 'kitty.conf').write_text('font_family      Red Hat Mono\nfont_size 11\n')
        self.env = os.environ.copy()
        self.env['HOME'] = str(self.home)
        self.env['XDG_CONFIG_HOME'] = str(self.config)
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.env.pop('WAYLAND_DISPLAY', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        return subprocess.run(
            [sys.executable, str(HELPER), *args],
            env=self.env, capture_output=True, text=True, check=False,
        )

    def test_defaults_off_and_readonly_status(self):
        res = self.run_helper('status', '--json')
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertFalse(data['enabled'])
        self.assertEqual(data['default_size'], 0.0)
        self.assertEqual(data['kitty_conf_size'], 11.0)
        self.assertFalse((self.config / 'fontctl/kitty-monitors.json').exists())
        ks = self.run_helper('kitty-size')
        self.assertEqual(ks.stdout.strip(), '')

    def test_set_validation_and_persistence(self):
        bad = self.run_helper('set', '--default', '2')
        self.assertNotEqual(bad.returncode, 0)
        res = self.run_helper(
            'set', '--enabled', 'true', '--default', '9.5',
            '--monitor', 'desc:AOC 27G2G4 0x00000A71=9.5',
            '--monitor', 'HDMI-A-1=11.5',
            '--json',
        )
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertTrue(data['enabled'])
        self.assertEqual(data['default_size'], 9.5)
        self.assertEqual(self.run_helper('kitty-size').stdout.strip(), '9.5')

        # Disabling suppresses kitty-size override while preserving saved sizes.
        res_off = self.run_helper('set', '--enabled', 'false', '--json')
        self.assertEqual(res_off.returncode, 0, res_off.stderr)
        self.assertEqual(self.run_helper('kitty-size').stdout.strip(), '')
        saved = json.loads((self.config / 'fontctl/kitty-monitors.json').read_text())
        self.assertEqual(saved['monitors']['HDMI-A-1'], 11.5)

    def test_monitor_selectors_and_metrics(self):
        mod = load_module()
        aoc = {'name': 'DP-1', 'make': 'AOC', 'model': '27G2G4',
               'description': 'AOC 27G2G4 0x00000A71',
               'width': 1920, 'height': 1080, 'physicalWidth': 600, 'physicalHeight': 340}
        arzopa = {'name': 'HDMI-A-1', 'make': 'GWD', 'model': 'ARZOPA',
                  'description': r'GWD ARZOPA 5=\x9d\x16%\xf9`S0001',
                  'width': 1920, 'height': 1080, 'physicalWidth': 360, 'physicalHeight': 200}
        self.assertEqual(mod.monitor_selector(aoc), 'desc:AOC 27G2G4 0x00000A71')
        self.assertEqual(mod.monitor_selector(arzopa), 'HDMI-A-1')
        self.assertEqual(mod.monitor_metrics(aoc), (27.2, 81))
        self.assertEqual(mod.monitor_metrics(arzopa), (16.2, 136))

        cfg = mod.normalize_config({
            'enabled': True, 'default_size': 9.5,
            'monitors': {'desc:AOC 27G2G4 0x00000A71': 9.5, 'HDMI-A-1': 11.5},
        })
        self.assertEqual(mod.effective_size_for_monitor(cfg, aoc, 11.0), 9.5)
        self.assertEqual(mod.effective_size_for_monitor(cfg, arzopa, 11.0), 11.5)

    def test_fontctl_preview_respects_enabled_override_and_explicit_flag(self):
        # Disabled: preset uses its built-in Kitty size (atelier = 11pt).
        r1 = subprocess.run(['bash', str(FONTCTL), 'preset', 'atelier', '--preview'],
                            env=self.env, capture_output=True, text=True, check=True)
        self.assertIn('11pt', r1.stdout)
        self.assertNotIn('(per-monitor default)', r1.stdout)

        # Enabled with default_size=9.5: preset inherits 9.5pt.
        self.run_helper('set', '--enabled', 'true', '--default', '9.5')
        r2 = subprocess.run(['bash', str(FONTCTL), 'preset', 'atelier', '--preview'],
                            env=self.env, capture_output=True, text=True, check=True)
        self.assertIn('9.5pt (per-monitor default)', r2.stdout)

        # Explicit CLI --kitty-size overrides the saved default.
        r3 = subprocess.run(['bash', str(FONTCTL), 'preset', 'atelier', '--kitty-size', '8.5', '--preview'],
                            env=self.env, capture_output=True, text=True, check=True)
        self.assertIn('8.5pt', r3.stdout)
        self.assertNotIn('(per-monitor default)', r3.stdout)

    def test_fontctl_catalog_exposes_full_specimen_metadata(self):
        res = subprocess.run(['bash', str(FONTCTL), 'preset', 'catalog'],
                             env=self.env, capture_output=True, text=True, check=True)
        profiles = json.loads(res.stdout)
        self.assertEqual(len(profiles), 26)
        for p in profiles:
            for field in ('id', 'label', 'group', 'description', 'ui', 'mono', 'title',
                          'numbers', 'reading', 'expressive', 'uiSize', 'monoSize', 'titleSize', 'kittySize'):
                self.assertIn(field, p, (p.get('id'), field))
            self.assertGreater(p['uiSize'], 0)
            self.assertGreater(p['monoSize'], 0)
            self.assertGreater(p['titleSize'], 0)
            self.assertGreater(p['kittySize'], 0)

    def test_lua_hook_only_fires_on_open_and_cross_monitor_move(self):
        lua = shutil_which('lua') or shutil_which('luajit')
        if not lua:
            self.skipTest('lua interpreter not installed')
        harness = f'''
local handlers = {{}}
local cmds = {{}}
local windows = {{
    {{address = "0x1", pid = 1001, class = "kitty", monitor = {{id = 0}}, workspace = {{id = 1, monitor = {{id = 0}}}}}},
}}
hl = {{
    on = function(ev, fn) handlers[ev] = fn end,
    get_windows = function() return windows end,
    exec_cmd = function(cmd) table.insert(cmds, cmd) end,
    timer = function(fn) fn() end,
}}
dofile({json.dumps(str(LUA_HOOK))})
assert(#cmds == 0, "seeding must not exec")
-- Same-monitor workspace move must NOT spawn helper.
handlers["window.move_to_workspace"](windows[1], {{id = 2, monitor = {{id = 0}}}})
assert(#cmds == 0, "same-monitor move should not exec")
-- Cross-monitor move MUST spawn helper for pid 1001.
windows[1].monitor = {{id = 1}}
handlers["window.move_to_workspace"](windows[1], {{id = 6, monitor = {{id = 1}}}})
assert(#cmds == 1 and cmds[1]:find("--pid 1001", 1, true), "cross-monitor move missed")
-- Opening a new Kitty window spawns helper with --wait-socket.
local w2 = {{address = "0x2", pid = 2002, class = "kitty", monitor = {{id = 1}}, workspace = {{id = 6, monitor = {{id = 1}}}}}}
handlers["window.open"](w2)
assert(#cmds == 2 and cmds[2]:find("--pid 2002 --on-event --wait-socket", 1, true), "window.open missed")
-- Non-kitty windows are ignored.
handlers["window.open"]({{address = "0x3", pid = 3003, class = "firefox", monitor = {{id = 0}}}})
assert(#cmds == 2, "non-kitty should not exec")
print("LUA_OK")
'''
        res = subprocess.run([lua, '-e', harness], capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn('LUA_OK', res.stdout)


def shutil_which(cmd):
    for d in os.environ.get('PATH', '').split(os.pathsep):
        p = Path(d) / cmd
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return None


if __name__ == '__main__':
    unittest.main()
