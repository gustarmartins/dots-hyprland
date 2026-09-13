#!/usr/bin/env python3
"""Create a runtime Matugen config that preserves unwritable theme targets."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path


SECTION_RE = re.compile(r"^\s*\[([^]]+)]\s*(?:#.*)?$")
OUTPUT_RE = re.compile(r"^\s*output_path\s*=\s*(['\"])(.*?)\1\s*(?:#.*)?$")


def nearest_existing_parent(path: Path) -> Path:
    candidate = path
    while not candidate.exists() and not candidate.is_symlink():
        if candidate.parent == candidate:
            break
        candidate = candidate.parent
    return candidate


def writable_output(path_value: str) -> tuple[bool, Path]:
    expanded = Path(os.path.expandvars(os.path.expanduser(path_value)))
    candidate = expanded if expanded.exists() or expanded.is_symlink() else nearest_existing_parent(expanded.parent)
    return os.access(candidate, os.W_OK), candidate


def filter_config(source: str) -> tuple[str, list[tuple[str, str, Path]]]:
    blocks: list[tuple[str | None, list[str]]] = []
    section_name: str | None = None
    section_lines: list[str] = []

    for line in source.splitlines(keepends=True):
        match = SECTION_RE.match(line)
        if match:
            blocks.append((section_name, section_lines))
            section_name = match.group(1)
            section_lines = [line]
        else:
            section_lines.append(line)
    blocks.append((section_name, section_lines))

    output: list[str] = []
    skipped: list[tuple[str, str, Path]] = []
    for name, lines in blocks:
        if not name or not name.startswith("templates."):
            output.extend(lines)
            continue

        output_path = None
        for line in lines:
            match = OUTPUT_RE.match(line)
            if match:
                output_path = match.group(2)
                break
        if output_path is None:
            output.extend(lines)
            continue

        writable, checked_path = writable_output(output_path)
        if writable:
            output.extend(lines)
        else:
            skipped.append((name.removeprefix("templates."), output_path, checked_path))

    return "".join(output), skipped


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Filter unwritable Matugen outputs")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    filtered, skipped = filter_config(args.input.read_text(encoding="utf-8"))
    atomic_write(args.output, filtered)
    for name, configured_path, checked_path in skipped:
        print(
            f"[matugen-config] Skipping {name}: output is not writable "
            f"({configured_path} -> {checked_path})",
            file=os.sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
