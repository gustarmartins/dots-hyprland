"""Execute generated Lua without changing desktop settings. Requires Lua 5.4+."""
import runpy
import shutil
import subprocess
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
effects = runpy.run_path(str(REPOSITORY / "dots/.local/bin/desktop-effects"))
effects["profile_path"].__globals__["ANIM_DIR"] = (
    REPOSITORY / "dots/.config/hypr/custom/animations"
)
LUA = shutil.which("lua")
CAPTURE = '''
local nodes = {}
hl = {
    config = function() end,
    curve = function() end,
    gesture = function() end,
    layer_rule = function() end,
    animation = function(a) nodes[a.leaf] = a end,
}
'''
PRINT = '''
for leaf, a in pairs(nodes) do
    print(table.concat({leaf, a.style or "", tostring(a.speed or 0),
                       a.spring or a.bezier or ""}, "\t"))
end
'''


@unittest.skipUnless(LUA, "Lua is required to evaluate the generated configuration")
class WorkspaceMotionTests(unittest.TestCase):
    def render(self, source, style, travel):
        settings = effects["DEFAULT"] | {
            "animation_profile": "aether_fusion.lua",
            "motion_source": source,
            "profile_tempo": 115,
        }
        prefix = "profile_" if source == "profile" else ""
        settings[prefix + "workspace_style"] = style
        settings[prefix + "travel"] = travel
        generated = effects["render"](settings)
        result = subprocess.run(
            [LUA, "-"], input=CAPTURE + generated + PRINT,
            text=True, capture_output=True, check=True,
        )
        return {row[0]: row[1:] for row in
                (line.split("\t") for line in result.stdout.splitlines())}

    def test_opaque_slides_always_clear_the_previous_workspace(self):
        for source in ("custom", "profile"):
            for travel in (0, 10, 100):
                with self.subTest(source=source, travel=travel):
                    nodes = self.render(source, "slide", travel)
                    for leaf in ("workspaces", "workspacesIn", "workspacesOut"):
                        self.assertEqual(nodes[leaf][0], "slide 100%")

    def test_glides_keep_their_requested_travel(self):
        for source in ("custom", "profile"):
            for style in ("slidefade", "slidefadevert"):
                for travel in (0, 10, 100):
                    with self.subTest(source=source, style=style, travel=travel):
                        nodes = self.render(source, style, travel)
                        for leaf in ("workspaces", "workspacesIn", "workspacesOut"):
                            self.assertEqual(nodes[leaf][0], f"{style} {travel}%")

    def test_fade_has_no_spatial_travel(self):
        for source in ("custom", "profile"):
            nodes = self.render(source, "fade", 10)
            for leaf in ("workspaces", "workspacesIn", "workspacesOut"):
                self.assertEqual(nodes[leaf][0], "fade")

    def test_profile_timing_and_other_animation_families_are_preserved(self):
        slide = self.render("profile", "slide", 10)
        preset = self.render("profile", "preset", -1)
        for leaf in ("workspaces", "workspacesIn", "workspacesOut"):
            self.assertEqual(slide[leaf][1:], preset[leaf][1:])
            self.assertEqual(preset[leaf][0], "slidefade 32%")
        self.assertAlmostEqual(float(slide["workspacesIn"][1]), 6.44)
        self.assertAlmostEqual(float(slide["workspacesOut"][1]), 5.52)
        self.assertEqual(slide["workspacesIn"][2], "aetherSpace")
        for leaf in preset.keys() - {"workspaces", "workspacesIn", "workspacesOut"}:
            self.assertEqual(slide[leaf], preset[leaf], leaf)


if __name__ == "__main__":
    unittest.main()
