#!/usr/bin/env -S\_/bin/sh\_-c\_"source\_\$(eval\_echo\_\$ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate&&exec\_python\_-E\_"\$0"\_"\$@""
"""Generate Material compatibility variables and a color-safe ANSI palette.

Matugen owns wallpaper extraction and the desktop Material palette.  This
script consumes Matugen's exact source/material colors and derives terminal
colors without repurposing the xterm 256-color cube.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

from PIL import Image
from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
from materialyoucolor.hct import Hct
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score
from materialyoucolor.utils.color_utils import argb_from_rgb, rgba_from_argb
from materialyoucolor.utils.math_utils import (
    difference_degrees,
    rotation_direction,
    sanitize_degrees_double,
)


HEX_COLOR_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
TERM_KEYS = tuple(f"term{index}" for index in range(16))
CHROMATIC_TERM_INDEXES = (*range(1, 7), *range(9, 15))


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def normalize_hex(value: str) -> str:
    value = value.strip()
    if not HEX_COLOR_RE.fullmatch(value):
        raise ValueError(f"invalid RGB color: {value!r}")
    return f"#{value.lstrip('#').upper()}"


def rgba_to_hex(rgba) -> str:
    return "#{:02X}{:02X}{:02X}".format(*map(round, rgba[:3]))


def argb_to_hex(argb: int) -> str:
    return rgba_to_hex(rgba_from_argb(argb))


def hex_to_argb(hex_code: str) -> int:
    value = normalize_hex(hex_code)
    return argb_from_rgb(
        int(value[1:3], 16),
        int(value[3:5], 16),
        int(value[5:7], 16),
    )


def display_color(argb: int) -> str:
    red, green, blue, _ = rgba_from_argb(argb)
    return f"\x1b[48;2;{round(red)};{round(green)};{round(blue)}m   \x1b[0m"


def calculate_optimal_size(
    width: int, height: int, bitmap_size: int
) -> tuple[int, int]:
    image_area = width * height
    bitmap_area = bitmap_size**2
    scale = math.sqrt(bitmap_area / image_area) if image_area > bitmap_area else 1
    return max(1, round(width * scale)), max(1, round(height * scale))


def source_color_from_image(path: str, bitmap_size: int) -> tuple[int, tuple[int, int], tuple[int, int]]:
    with Image.open(path) as source_image:
        if source_image.format == "GIF" and getattr(source_image, "n_frames", 1) > 1:
            source_image.seek(1)
        image = source_image.convert("RGB")
    original_size = image.size
    resized_size = calculate_optimal_size(*original_size, bitmap_size)
    if resized_size != original_size:
        image = image.resize(resized_size, Image.Resampling.BICUBIC)
    quantized = QuantizeCelebi(list(image.getdata()), 128)
    return Score.score(quantized)[0], original_size, resized_size


def harmonize(
    design_color: int,
    source_color: int,
    threshold: float = 15,
    harmony: float = 0.15,
) -> int:
    """Shift hue toward the wallpaper while preserving source tone/chroma."""
    design_hct = Hct.from_int(design_color)
    source_hct = Hct.from_int(source_color)
    hue_difference = difference_degrees(design_hct.hue, source_hct.hue)
    rotation_degrees = min(
        hue_difference * clamp(harmony, 0.0, 1.0),
        clamp(threshold, 0.0, 180.0),
    )
    output_hue = sanitize_degrees_double(
        design_hct.hue
        + rotation_degrees
        * rotation_direction(design_hct.hue, source_hct.hue)
    )
    return Hct.from_hct(output_hue, design_hct.chroma, design_hct.tone).to_int()


def adjust_contrast_tone(
    argb: int,
    strength: float,
    darkmode: bool,
    bright: bool,
) -> int:
    """Move tone toward a safe target instead of multiplying it to white."""
    color = Hct.from_int(argb)
    strength = clamp(strength, 0.0, 1.0)
    target_tone = (82.0 if bright else 70.0) if darkmode else (30.0 if bright else 38.0)

    needs_more_contrast = (
        color.tone < target_tone if darkmode else color.tone > target_tone
    )
    if not needs_more_contrast or strength == 0:
        return argb

    output_tone = color.tone + (target_tone - color.tone) * strength
    return Hct.from_hct(color.hue, color.chroma, output_tone).to_int()


def monochromize(argb: int) -> int:
    color = Hct.from_int(argb)
    return Hct.from_hct(color.hue, 0.0, color.tone).to_int()


def scheme_class(scheme_name: str):
    if scheme_name == "scheme-fruit-salad":
        from materialyoucolor.scheme.scheme_fruit_salad import SchemeFruitSalad

        return SchemeFruitSalad
    if scheme_name == "scheme-expressive":
        from materialyoucolor.scheme.scheme_expressive import SchemeExpressive

        return SchemeExpressive
    if scheme_name == "scheme-monochrome":
        from materialyoucolor.scheme.scheme_monochrome import SchemeMonochrome

        return SchemeMonochrome
    if scheme_name == "scheme-rainbow":
        from materialyoucolor.scheme.scheme_rainbow import SchemeRainbow

        return SchemeRainbow
    if scheme_name == "scheme-tonal-spot":
        from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot

        return SchemeTonalSpot
    if scheme_name == "scheme-neutral":
        from materialyoucolor.scheme.scheme_neutral import SchemeNeutral

        return SchemeNeutral
    if scheme_name == "scheme-fidelity":
        from materialyoucolor.scheme.scheme_fidelity import SchemeFidelity

        return SchemeFidelity
    if scheme_name == "scheme-content":
        from materialyoucolor.scheme.scheme_content import SchemeContent

        return SchemeContent

    from materialyoucolor.scheme.scheme_vibrant import SchemeVibrant

    return SchemeVibrant


def generate_material_colors(
    source_hct: Hct, scheme_name: str, darkmode: bool
) -> dict[str, str]:
    scheme = scheme_class(scheme_name)(source_hct, darkmode, 0.0)
    colors: dict[str, str] = {}
    for attribute in vars(MaterialDynamicColors):
        dynamic_color = getattr(MaterialDynamicColors, attribute)
        if hasattr(dynamic_color, "get_hct"):
            colors[attribute] = rgba_to_hex(dynamic_color.get_hct(scheme).to_rgba())

    if darkmode:
        colors.update(
            success="#B5CCBA",
            onSuccess="#213528",
            successContainer="#374B3E",
            onSuccessContainer="#D1E9D6",
        )
    else:
        colors.update(
            success="#4F6354",
            onSuccess="#FFFFFF",
            successContainer="#D1E8D5",
            onSuccessContainer="#0C1F13",
        )
    return colors


def snake_to_lower_camel(name: str) -> str:
    first, *rest = name.split("_")
    return first + "".join(part[:1].upper() + part[1:] for part in rest)


def load_matugen_material_colors(path: str) -> dict[str, str]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("Matugen color output must be a JSON object")

    colors: dict[str, str] = {}
    for name, value in raw.items():
        if isinstance(value, str) and HEX_COLOR_RE.fullmatch(value):
            colors[snake_to_lower_camel(name)] = normalize_hex(value)
    if "surface" not in colors or "onSurface" not in colors or "primary" not in colors:
        raise ValueError("Matugen color output is missing required Material roles")
    return colors


def load_terminal_scheme(path: str, darkmode: bool) -> dict[str, str]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    palette = raw["dark" if darkmode else "light"]
    missing = set(TERM_KEYS) - set(palette)
    if missing:
        raise ValueError(f"terminal scheme is missing: {', '.join(sorted(missing))}")
    return {key: normalize_hex(palette[key]) for key in TERM_KEYS}


def material_color(material: dict[str, str], *roles: str) -> str:
    for role in roles:
        if role in material:
            return material[role]
    raise KeyError(f"none of the Material roles are available: {', '.join(roles)}")


def generate_terminal_colors(
    source_color: int,
    source_palette: dict[str, str],
    material_colors: dict[str, str],
    *,
    darkmode: bool,
    monochrome: bool,
    harmony: float,
    harmonize_threshold: float,
    contrast_boost: float,
    blend_background_foreground: bool,
) -> dict[str, str]:
    terminal: dict[str, str] = {}

    for index in range(16):
        key = f"term{index}"
        color = hex_to_argb(source_palette[key])
        if index in CHROMATIC_TERM_INDEXES:
            if monochrome:
                color = monochromize(color)
            else:
                color = harmonize(
                    color,
                    source_color,
                    threshold=harmonize_threshold,
                    harmony=harmony,
                )
            color = adjust_contrast_tone(
                color,
                contrast_boost,
                darkmode,
                bright=index >= 9,
            )
        elif monochrome:
            color = monochromize(color)
        terminal[key] = argb_to_hex(color)

    if blend_background_foreground:
        terminal["termBackground"] = material_color(
            material_colors, "surfaceContainerLow", "surface", "background"
        )
        terminal["termForeground"] = material_color(
            material_colors, "onSurface", "onBackground"
        )
        terminal["termCursor"] = material_color(material_colors, "primary")
    else:
        terminal["termBackground"] = terminal["term0"]
        terminal["termForeground"] = terminal["term7"]
        terminal["termCursor"] = terminal["termForeground"]

    return terminal


def scss_output(
    material_colors: dict[str, str],
    terminal_colors: dict[str, str],
    *,
    darkmode: bool,
    transparent: bool,
) -> str:
    lines = [
        f"$darkmode: {darkmode};",
        f"$transparent: {transparent};",
    ]
    lines.extend(f"${name}: {value};" for name, value in material_colors.items())
    lines.extend(f"${name}: {value};" for name, value in terminal_colors.items())
    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Material and terminal color generation")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--path", help="generate the source color from an image")
    source.add_argument("--color", help="generate from a #RRGGBB source color")
    parser.add_argument("--size", type=int, default=128, help="image sampling size")
    parser.add_argument("--mode", choices=("dark", "light"), default="dark")
    parser.add_argument("--scheme", default="scheme-vibrant", help="Material scheme")
    parser.add_argument("--smart", action="store_true", help="use neutral for gray images")
    parser.add_argument(
        "--transparency",
        choices=("opaque", "transparent"),
        default="opaque",
    )
    parser.add_argument("--termscheme", help="JSON containing dark/light ANSI anchors")
    parser.add_argument(
        "--material-colors",
        help="Matugen colors.json; its roles override locally generated Material roles",
    )
    parser.add_argument(
        "--harmony",
        type=float,
        default=0.15,
        help="0-1 fraction of ANSI hue distance shifted toward the source color",
    )
    parser.add_argument(
        "--harmonize_threshold",
        type=float,
        default=15,
        help="0-180 maximum ANSI hue rotation in degrees",
    )
    parser.add_argument(
        "--term_fg_boost",
        type=float,
        default=0.50,
        help="0-1 bounded ANSI contrast adjustment (legacy option name)",
    )
    parser.add_argument(
        "--blend_bg_fg",
        action="store_true",
        help="derive terminal background/foreground/cursor from Material roles",
    )
    parser.add_argument("--cache", help="compatibility path for the selected source color")
    parser.add_argument("--debug", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    darkmode = args.mode == "dark"
    transparent = args.transparency == "transparent"
    original_size = resized_size = None

    if args.path:
        source_color, original_size, resized_size = source_color_from_image(
            args.path, args.size
        )
    else:
        source_color = hex_to_argb(args.color)

    source_hct = Hct.from_int(source_color)
    if args.smart and source_hct.chroma < 20:
        args.scheme = "scheme-neutral"

    if args.cache:
        Path(args.cache).write_text(argb_to_hex(source_color), encoding="utf-8")

    material_colors = generate_material_colors(source_hct, args.scheme, darkmode)
    if args.material_colors:
        material_colors.update(load_matugen_material_colors(args.material_colors))
    material_colors["primary_paletteKeyColor"] = argb_to_hex(source_color)

    terminal_colors: dict[str, str] = {}
    source_terminal_palette: dict[str, str] = {}
    if args.termscheme:
        source_terminal_palette = load_terminal_scheme(args.termscheme, darkmode)
        terminal_colors = generate_terminal_colors(
            source_color,
            source_terminal_palette,
            material_colors,
            darkmode=darkmode,
            monochrome=args.scheme == "scheme-monochrome",
            harmony=args.harmony,
            harmonize_threshold=args.harmonize_threshold,
            contrast_boost=args.term_fg_boost,
            blend_background_foreground=args.blend_bg_fg,
        )

    if not args.debug:
        print(
            scss_output(
                material_colors,
                terminal_colors,
                darkmode=darkmode,
                transparent=transparent,
            ),
            end="",
        )
        return 0

    if args.path:
        print("\n--------------Image properties-----------------")
        print(f"Image size: {original_size[0]} x {original_size[1]}")
        print(f"Resized image: {resized_size[0]} x {resized_size[1]}")
    print("\n---------------Selected color------------------")
    print(f"Dark mode: {darkmode}")
    print(f"Scheme: {args.scheme}")
    print(f"Accent color: {display_color(source_color)} {argb_to_hex(source_color)}")
    print(
        f"HCT: {source_hct.hue:.2f}  {source_hct.chroma:.2f}  "
        f"{source_hct.tone:.2f}"
    )
    print("\n---------------Material colors-----------------")
    for name, value in material_colors.items():
        print(f"{name.ljust(32)} : {display_color(hex_to_argb(value))}  {value}")
    if terminal_colors:
        print("\n-------------Terminal ANSI colors--------------")
        for name in TERM_KEYS:
            source_value = source_terminal_palette[name]
            output_value = terminal_colors[name]
            print(
                f"{name.ljust(6)} : {display_color(hex_to_argb(source_value))} "
                f"{source_value} -> {display_color(hex_to_argb(output_value))} "
                f"{output_value}"
            )
        print(f"background: {terminal_colors['termBackground']}")
        print(f"foreground: {terminal_colors['termForeground']}")
    print("-----------------------------------------------")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
