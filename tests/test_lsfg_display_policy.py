#!/usr/bin/env python3
"""Execute the tile's real Lua commands against inert monitor/config APIs."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT/'dots/.config/quickshell/ii/modules/common/models/quickToggles/LsfgToggle.qml'


def evaluate(action, policy):
    commands = re.findall(r'applyMode.command = (\[[^\n]+\])', QML.read_text())
    argv = json.loads(commands[action])
    assert argv[:2] == ['bash','-c']
    ipc = shlex.split(argv[2])
    assert ipc[:2] == ['hyprctl','eval'] and len(ipc) == 3
    setup = '''
local profiles={aoc={output="desc:AOC fixture",mode="1920x1080@144.0",vrr=POLICY,scale=1,position="0x0"}}
package.loaded.monitors=profiles
local writes=0
hl={
 monitor=function(p)
  assert(p.output=="desc:AOC fixture", "peer display changed")
  assert(p.scale==1 and p.position=="0x0", "layout changed")
  writes=writes+1
  io.write(p.mode.."|"..p.vrr.."\\n")
 end,
 config=function() error("global configuration must remain untouched") end
}
'''.replace('POLICY',str(policy))
    verify = '\nassert(writes==1);assert(profiles.aoc.mode=="1920x1080@144.0");assert(profiles.aoc.vrr=='+str(policy)+')\n'
    return subprocess.check_output(['lua','-'],input=setup+ipc[2]+verify,text=True).strip()


class DisplayPolicy(unittest.TestCase):
    def test_enable_only_changes_aoc_and_preserves_saved_profile(self):
        for policy in (-1,0,1,2,3):
            with self.subTest(policy=policy):
                self.assertEqual(evaluate(0,policy),'1920x1080@120.0|0')

    def test_disable_restores_every_supported_saved_policy(self):
        for policy in (-1,0,1,2,3):
            with self.subTest(policy=policy):
                self.assertEqual(evaluate(1,policy),'1920x1080@144.0|'+str(policy))


if __name__ == '__main__':
    unittest.main()
