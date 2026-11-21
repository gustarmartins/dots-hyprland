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


if __name__ == '__main__':
    unittest.main()
