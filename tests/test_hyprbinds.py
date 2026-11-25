#!/usr/bin/env python3
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).resolve().parents[1] / 'dots/.local/bin/hyprbinds'
inspector = runpy.run_path(str(TOOL))


class KeybindSearch(unittest.TestCase):
    def test_registration_and_description_search(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            root = home / 'test config/hypr'
            defaults = root / 'hyprland'
            custom = root / 'custom'
            defaults.mkdir(parents=True)
            custom.mkdir()
            (defaults / 'keybinds.lua').write_text('hl.on("input.keyboard.key", function() error("callback ran") end)\n'
                'hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"), {description="App: Terminal"})\n')
            (custom / 'keybinds.lua').write_text('hl.window_rule({enabled=#hl.get_windows()==0})\n'
                'hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("ii-task-manager"), {description="App: Task manager"})\n')
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(root.parent))
            for query, combo in [('terminal','SUPER + Return'),('kitty','SUPER + Return'),('super,enter','SUPER + Return'),
                                 ('task manager','CTRL + SHIFT + Escape'),('shift+ctrl+esc','CTRL + SHIFT + Escape')]:
                info = json.loads(subprocess.check_output([TOOL, '--lua-only', '--json', query], env=env, text=True))
                self.assertEqual([row['combo'] for row in info], [combo])
                self.assertTrue(Path(info[0]['file']).is_file())

    def test_runtime_supplement_preserves_source_and_physical_modifiers(self):
        entry = inspector['KeybindEntry']({'key':'SUPER_L','description':'Press','file':'keys.lua','line':3})
        rows = [dict(key='SUPER_L', modmask=64, description='Press'),dict(key='F13', modmask=68, description='Plugin action')]
        data = subprocess.CompletedProcess([],0,stdout=json.dumps(rows))
        with patch('subprocess.run', return_value=data):
            result=[entry]
            inspector['add_live_bindings'](result)
        self.assertEqual([(r.combo_formatted,r.source_type) for r in result],[('Super_L','lua'),('SUPER + CTRL + F13','live')])

    def test_combo_and_key_queries_never_pollute_with_text_matches(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            root = home / 'hypr'
            defaults = root / 'hyprland'
            custom = root / 'custom'
            defaults.mkdir(parents=True)
            custom.mkdir()
            (defaults / 'keybinds.lua').write_text(
                'hl.bind("SUPER + CTRL + R", hl.dsp.exec_cmd("hyprctl reload"), {description="Shell: Reload"})\n'
                'hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"), {description="Utilities: Record region"})\n'
                'hl.bind("SUPER + ALT + SHIFT + R", hl.dsp.exec_cmd("record.sh --sound"), {description="Utilities: Record screen"})\n'
                'hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd("record.sh --fullscreen"))\n'
                'hl.bind("SUPER + Space", hl.dsp.exec_cmd("switch-layout"), {description="User: Toggle keyboard layout"})\n'
                'hl.bind("SUPER + 1", function() return 1 end, {description="Workspace: Focus 1"})\n'
                'hl.bind("SUPER + Up", hl.dsp.focus({direction="u"}), {description="Window: Focus Up"})\n'
                'hl.bind("SUPER + Left", hl.dsp.focus({direction="l"}), {description="Window: Focus Left"})\n'
                'hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle"), {description="Shell: Toggle left sidebar"})\n'
                'hl.bind("SUPER + F1", hl.dsp.exec_cmd("gpu-mode"), {description="User: Toggle GPU"})\n'
                'hl.bind("SUPER + F10", hl.dsp.exec_cmd("geo-toggle"), {description="User: Toggle geometry"})\n'
                'hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"), {description="Utilities: Screenshot"})\n'
                'hl.bind("CTRL + Print", hl.dsp.exec_cmd("grim file.png"), {description="Utilities: Screenshot file"})\n'
                'hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd("awk \'{print $1}\'"), {description="Utilities: OCR"})\n'
                'hl.bind("SUPER + Q", hl.dsp.window.close(), {description="Window: Close"})\n'
            )
            (custom / 'keybinds.lua').write_text(
                'hl.unbind("SUPER + Q")\n'
                'hl.bind("SUPER + Q", function() hl.dispatch(hl.dsp.window.close()) end, {description="Window: Close visible"})\n'
            )
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(temp))

            def run_json(*args):
                return json.loads(subprocess.check_output([TOOL, '--lua-only', '--json', *args], env=env, text=True))

            # Combo queries with spaces/+ must only return R bindings, never unrelated SUPER binds.
            expected_super_r = ['SUPER + CTRL + R', 'SUPER + SHIFT + R', 'SUPER + ALT + SHIFT + R', 'CTRL + ALT + R']
            for args in (['super', '+', 'r'], ['super + r'], ['super r'], ['super+r'], ['r + super']):
                self.assertEqual([row['combo'] for row in run_json(*args)], expected_super_r, msg=f'query={args}')

            # Unassigned combo display explicitly says unassigned and prints no text section.
            out = subprocess.check_output([TOOL, '--lua-only', '--no-color', 'super', '+', 'r'], env=env, text=True)
            self.assertIn('SUPER + R is currently unassigned', out)
            self.assertNotIn('MATCHES BY DESCRIPTION', out)

            # Single key queries (including quoted "r") return all bindings on R sorted by mod count -> mod order.
            expected_r = ['SUPER + CTRL + R', 'SUPER + SHIFT + R', 'CTRL + ALT + R', 'SUPER + ALT + SHIFT + R']
            for q in ('r', 'R', '"r"', "'r'"):
                self.assertEqual([row['combo'] for row in run_json(q)], expected_r, msg=f'query={q}')

            # Named keys must not bleed into unrelated words (workspace, super, F10, Lua return, awk print).
            self.assertEqual([row['combo'] for row in run_json('space')], ['SUPER + Space'])
            self.assertEqual([row['combo'] for row in run_json('up')], ['SUPER + Up'])
            self.assertEqual([row['combo'] for row in run_json('f1')], ['SUPER + F1'])
            self.assertEqual([row['combo'] for row in run_json('return')], [])
            self.assertEqual([row['combo'] for row in run_json('print')], ['Print', 'CTRL + Print'])
            print_out = subprocess.check_output([TOOL, '--lua-only', '--no-color', 'print'], env=env, text=True)
            self.assertIn('CTRL + Print', print_out)
            self.assertNotIn('SUPER + SHIFT + X', print_out)

            # Multi-word text query starting with a key word ('left sidebar') searches text, not Left arrow key.
            self.assertEqual([row['combo'] for row in run_json('left sidebar')], ['SUPER + A'])

            # Modifier + text query filters to bindings with that modifier.
            self.assertEqual([row['combo'] for row in run_json('super reload')], ['SUPER + CTRL + R'])

            # Active custom binding sorts ahead of unbound default on exact match.
            q_rows = run_json('super + q')
            self.assertEqual([row['combo'] for row in q_rows], ['SUPER + Q', 'SUPER + Q'])
            self.assertEqual([row['unbound'] for row in q_rows], [False, True])

    def test_extract_function_body_stops_at_named_callback_bind(self):
        with tempfile.TemporaryDirectory() as temp:
            lua_file = Path(temp) / 'super_tap.lua'
            lua_file.write_text(
                'local function arm() end\n'
                'hl.bind("SUPER + SUPER_L", arm, { description = "Tap" })\n'
                '-- Observe unrelated comment mentioning obs\n'
                'local function cancel() end\n'
            )
            snippet = inspector['extract_function_body'](str(lua_file), 2)
            self.assertIn('hl.bind("SUPER + SUPER_L", arm', snippet)
            self.assertNotIn('Observe', snippet)
            self.assertNotIn('cancel', snippet)


if __name__ == '__main__':
    unittest.main()
