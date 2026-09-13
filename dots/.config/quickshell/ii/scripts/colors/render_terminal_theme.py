#!/usr/bin/env python3
"""Render terminal consumers atomically from generated SCSS variables."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path


COLOR_RE = re.compile(r"^\$(\w+):\s*(#[0-9A-Fa-f]{6});\s*$", re.MULTILINE)
PLACEHOLDER_RE = re.compile(r"#\$(\w+) #")
KITTY_INDEX_RE = re.compile(r"^color(\d+)\s+", re.MULTILINE)
ESC = b"\x1b"
ST = ESC + b"\\"


def parse_colors(path: Path) -> dict[str, str]:
    colors = {
        name: value.upper()
        for name, value in COLOR_RE.findall(path.read_text(encoding="utf-8"))
    }
    required = {
        *(f"term{index}" for index in range(16)),
        "termBackground",
        "termForeground",
        "termCursor",
    }
    missing = required - colors.keys()
    if missing:
        raise ValueError(f"generated colors are missing: {', '.join(sorted(missing))}")
    return colors


def render_template(path: Path, colors: dict[str, str]) -> str:
    source = path.read_text(encoding="utf-8")
    missing = sorted(set(PLACEHOLDER_RE.findall(source)) - colors.keys())
    if missing:
        raise ValueError(
            f"{path} references unavailable colors: {', '.join(missing)}"
        )
    rendered = PLACEHOLDER_RE.sub(lambda match: colors[match.group(1)], source)
    unresolved = PLACEHOLDER_RE.findall(rendered)
    if unresolved:
        raise ValueError(f"unresolved placeholders in {path}: {', '.join(unresolved)}")
    return rendered


def terminal_sequences(colors: dict[str, str], enabled: bool) -> bytes:
    def osc(payload: str) -> bytes:
        return ESC + b"]" + payload.encode("ascii") + ST

    if not enabled:
        return b"".join(osc(code) for code in ("104", "110", "111", "112"))

    output = [osc(f"4;{index};{colors[f'term{index}']}") for index in range(16)]
    output.extend(
        (
            osc(f"10;{colors['termForeground']}"),
            osc(f"11;{colors['termBackground']}"),
            osc(f"12;{colors['termCursor']}"),
        )
    )
    return b"".join(output)


def atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(file_descriptor, "wb") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render terminal theme consumers")
    parser.add_argument("--colors", type=Path, required=True)
    parser.add_argument("--kitty-template", type=Path, required=True)
    parser.add_argument("--kitty-output", type=Path, required=True)
    parser.add_argument("--starship-template", type=Path, required=True)
    parser.add_argument("--starship-output", type=Path, required=True)
    parser.add_argument("--sequences-output", type=Path, required=True)
    parser.add_argument("--enabled-file", type=Path, required=True)
    parser.add_argument("--enabled", choices=("true", "false"), required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    enabled = args.enabled == "true"
    colors = parse_colors(args.colors)
    kitty_theme = render_template(args.kitty_template, colors)
    starship_theme = render_template(args.starship_template, colors)

    overridden_indexes = {
        int(index) for index in KITTY_INDEX_RE.findall(kitty_theme) if int(index) > 15
    }
    if overridden_indexes:
        raise ValueError(
            "Kitty theme must preserve xterm indexes 16-255; found overrides for "
            + ", ".join(map(str, sorted(overridden_indexes)))
        )

    if not enabled:
        kitty_theme = "# Wallpaper-driven terminal theming is disabled.\n"

    atomic_write(args.kitty_output, kitty_theme.encode("utf-8"))
    atomic_write(args.starship_output, starship_theme.encode("utf-8"))
    atomic_write(args.sequences_output, terminal_sequences(colors, enabled))
    atomic_write(args.enabled_file, f"{args.enabled}\n".encode("ascii"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
