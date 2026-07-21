#!/usr/bin/env python3
"""Convert the repository's legacy Hyprland animation profiles to Lua."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ANIMATIONS = ROOT / "dots/.config/hypr/custom/animations"


def enabled(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def number(value: str) -> str:
    value = value.strip()
    float(value)
    return value


def quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def convert(source: Path) -> str:
    output = ["-- Generated from " + source.name + ". Keep the legacy profile as migration provenance."]
    global_enabled: bool | None = None

    for raw in source.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line in {"animations {", "}"}:
            continue

        compact = re.fullmatch(r"animations:enabled\s*=\s*(\S+)", line)
        if compact:
            global_enabled = enabled(compact.group(1))
            continue

        assignment = re.match(r"([A-Za-z]+)\s*=\s*(.*)", line)
        if not assignment:
            raise ValueError(f"{source}: unsupported line: {raw}")
        key, value = assignment.groups()

        if key == "enabled":
            global_enabled = enabled(value)
            continue

        parts = [part.strip() for part in value.split(",")]
        if key == "bezier":
            if len(parts) != 5:
                raise ValueError(f"{source}: malformed bezier: {raw}")
            name, x1, y1, x2, y2 = parts
            output.append(
                f"hl.curve({quoted(name)}, {{ type = \"bezier\", points = "
                f"{{{{ {number(x1)}, {number(y1)} }}, {{ {number(x2)}, {number(y2)} }}}} }})"
            )
            continue

        if key == "animation":
            if len(parts) < 2:
                raise ValueError(f"{source}: malformed animation: {raw}")
            leaf = parts[0]
            is_enabled = enabled(parts[1])
            fields = [f"leaf = {quoted(leaf)}", f"enabled = {str(is_enabled).lower()}"]
            if is_enabled:
                if len(parts) < 4:
                    raise ValueError(f"{source}: enabled animation lacks speed/curve: {raw}")
                fields.extend((f"speed = {number(parts[2])}", f"bezier = {quoted(parts[3])}"))
                style = ",".join(parts[4:]).strip()
                if style:
                    fields.append(f"style = {quoted(style)}")
            output.append("hl.animation({ " + ", ".join(fields) + " })")
            continue

        if key == "gesture":
            if len(parts) < 3:
                raise ValueError(f"{source}: malformed gesture: {raw}")
            direction, action = parts[1], parts[2]
            # Legacy Hyprland supplied the three-finger horizontal workspace
            # gesture implicitly. The Lua baseline supplies one catch-all
            # three-finger swipe instead, so the old "horizontal, unset"
            # directive must remove that exact Lua gesture before installing
            # the vertical replacement.
            if parts[0] == "3" and direction == "horizontal" and action == "unset":
                direction = "swipe"
            output.append(
                "hl.gesture({ fingers = " + number(parts[0]) + ", direction = "
                + quoted(direction) + ", action = " + quoted(action) + " })"
            )
            continue

        raise ValueError(f"{source}: unsupported directive: {raw}")

    if global_enabled is not None:
        output.insert(1, f"hl.config({{ animations = {{ enabled = {str(global_enabled).lower()} }} }})")
    output.append("")
    return "\n".join(output)


def main() -> None:
    for source in sorted(ANIMATIONS.glob("*.conf")):
        source.with_suffix(".lua").write_text(convert(source), encoding="utf-8")

    active_conf = ANIMATIONS / "active/active.conf"
    (ANIMATIONS / "active/active.lua").write_text(convert(active_conf), encoding="utf-8")


if __name__ == "__main__":
    main()
