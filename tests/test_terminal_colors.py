from __future__ import annotations

import importlib.util
import itertools
import re
import tempfile
import unittest
from pathlib import Path

from materialyoucolor.hct import Hct


REPOSITORY = Path(__file__).resolve().parents[1]
COLOR_DIR = REPOSITORY / "dots/.config/quickshell/ii/scripts/colors"
SCHEME_PATH = COLOR_DIR / "terminal/scheme-base.json"


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(module)
    return module


colors = load_module("generate_colors_material", COLOR_DIR / "generate_colors_material.py")
renderer = load_module("render_terminal_theme", COLOR_DIR / "render_terminal_theme.py")
matugen_config = load_module(
    "prepare_matugen_config", COLOR_DIR / "prepare_matugen_config.py"
)


def relative_luminance(value: str) -> float:
    channels = [int(value[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        channel / 12.92
        if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    brighter, darker = sorted(
        (relative_luminance(first), relative_luminance(second)), reverse=True
    )
    return (brighter + 0.05) / (darker + 0.05)


class TerminalPaletteTests(unittest.TestCase):
    source_colors = (
        "#FF0000",
        "#00FF00",
        "#0000FF",
        "#4BA4D8",
        "#808080",
        "#FF00FF",
        "#FFFF00",
    )

    def generate(self, darkmode: bool, source: str, **overrides):
        palette = colors.load_terminal_scheme(SCHEME_PATH, darkmode)
        material = {
            "surfaceContainerLow": "#181C20" if darkmode else "#F4F4F5",
            "onSurface": "#DFE3E7" if darkmode else "#1A1C1E",
            "primary": source,
        }
        options = {
            "darkmode": darkmode,
            "monochrome": False,
            "harmony": 0.15,
            "harmonize_threshold": 15,
            "contrast_boost": 0.50,
            "blend_background_foreground": True,
        }
        options.update(overrides)
        return colors.generate_terminal_colors(
            colors.hex_to_argb(source), palette, material, **options
        )

    def test_balanced_palette_stays_distinct_and_readable(self):
        indexes = (*range(1, 7), *range(9, 15))
        for darkmode, source in itertools.product((True, False), self.source_colors):
            with self.subTest(darkmode=darkmode, source=source):
                generated = self.generate(darkmode, source)
                ansi = [generated[f"term{index}"] for index in indexes]
                self.assertEqual(len(set(ansi)), len(ansi))
                self.assertGreaterEqual(
                    min(
                        contrast_ratio(value, generated["termBackground"])
                        for value in ansi
                    ),
                    4.45,
                )

                base_hues = [
                    Hct.from_int(colors.hex_to_argb(generated[f"term{index}"])).hue
                    for index in range(1, 7)
                ]
                hue_separation = [
                    min(abs(first - second), 360 - abs(first - second))
                    for first, second in itertools.combinations(base_hues, 2)
                ]
                self.assertGreaterEqual(min(hue_separation), 25)

    def test_maximum_contrast_cannot_turn_palette_white(self):
        generated = self.generate(
            True,
            "#4BA4D8",
            contrast_boost=1.0,
        )
        ansi = [
            generated[f"term{index}"]
            for index in (*range(1, 7), *range(9, 15))
        ]
        self.assertEqual(len(set(ansi)), len(ansi))
        self.assertNotIn("#FFFFFF", ansi)

    def test_monochrome_is_intentional(self):
        generated = self.generate(
            True,
            "#4BA4D8",
            monochrome=True,
        )
        for index in (*range(1, 7), *range(9, 15)):
            color = Hct.from_int(colors.hex_to_argb(generated[f"term{index}"]))
            self.assertLess(color.chroma, 4)


class TerminalRendererTests(unittest.TestCase):
    def test_renderer_preserves_xterm_extended_palette(self):
        material = colors.generate_material_colors(
            Hct.from_int(colors.hex_to_argb("#4BA4D8")),
            "scheme-tonal-spot",
            True,
        )
        terminal = colors.generate_terminal_colors(
            colors.hex_to_argb("#4BA4D8"),
            colors.load_terminal_scheme(SCHEME_PATH, True),
            material,
            darkmode=True,
            monochrome=False,
            harmony=0.15,
            harmonize_threshold=15,
            contrast_boost=0.50,
            blend_background_foreground=True,
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            scss = temporary / "colors.scss"
            scss.write_text(
                colors.scss_output(
                    material,
                    terminal,
                    darkmode=True,
                    transparent=False,
                ),
                encoding="utf-8",
            )
            parsed = renderer.parse_colors(scss)
            kitty = renderer.render_template(
                COLOR_DIR / "terminal/kitty-theme.conf", parsed
            )
            starship = renderer.render_template(
                COLOR_DIR / "terminal/starship.toml.in", parsed
            )
            sequences = renderer.terminal_sequences(parsed, True)

        self.assertNotRegex(kitty, r"#\$\w+ #")
        self.assertNotRegex(starship, r"#\$\w+ #")
        self.assertEqual(
            {int(index) for index in re.findall(r"^color(\d+)\s+", kitty, re.M)},
            set(range(16)),
        )
        self.assertTrue(all(f"\x1b]4;{index};".encode() in sequences for index in range(16)))
        self.assertFalse(any(f"\x1b]4;{index};".encode() in sequences for index in range(16, 256)))


class MatugenConfigTests(unittest.TestCase):
    def test_unwritable_template_is_skipped_without_touching_other_outputs(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            writable_output = temporary / "colors.json"
            protected_output = temporary / "protected.css"
            protected_output.symlink_to("/proc/version")
            source = f"""\
[config]
version_check = false

[templates.required]
input_path = '/tmp/required.in'
output_path = '{writable_output}'

[templates.protected]
input_path = '/tmp/protected.in'
output_path = '{protected_output}'
"""
            filtered, skipped = matugen_config.filter_config(source)

        self.assertIn("[templates.required]", filtered)
        self.assertNotIn("[templates.protected]", filtered)
        self.assertEqual([name for name, _, _ in skipped], ["protected"])


if __name__ == "__main__":
    unittest.main()
