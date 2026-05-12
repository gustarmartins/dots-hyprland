#!/usr/bin/env python3
"""
Exempt a window from the master_float forced size (1200x800).

Usage:
  exempt-float-size.py              Toggle exemption for focused window's CLASS
  exempt-float-size.py --title      Toggle exemption for focused window's TITLE
  exempt-float-size.py <class>      Add/toggle exemption for a specific class
  exempt-float-size.py --list       Show all currently exempted patterns
"""

import sys
import os
import re
import json
import subprocess

EXEMPT_FILE = os.path.expanduser("~/.config/hypr/custom/autofloat_exemptions.txt")


def notify(msg):
    subprocess.run(["notify-send", "Float Exempt", msg])


def get_active_window_info():
    result = subprocess.run(
        ["hyprctl", "activewindow", "-j"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None, None
    try:
        data = json.loads(result.stdout)
        return data.get("class"), data.get("title")
    except json.JSONDecodeError:
        return None, None


def escape_for_regex(s):
    """Escape special regex characters for safe matching."""
    return re.sub(r'([.\\+*?^$\[\]{}()|])', r'\\\1', s)


def read_exemptions():
    """Read exemption file, return list of non-comment, non-empty lines."""
    if not os.path.exists(EXEMPT_FILE):
        return []
    with open(EXEMPT_FILE, "r") as f:
        return [line.rstrip('\n') for line in f
                if line.strip() and not line.startswith('#')]


def write_exemptions(entries):
    """Write exemption list back, preserving the header comments."""
    header = ""
    if os.path.exists(EXEMPT_FILE):
        with open(EXEMPT_FILE, "r") as f:
            lines = f.readlines()
        # Keep leading comment block
        header_lines = []
        for line in lines:
            if line.startswith('#') or line.strip() == '':
                header_lines.append(line)
            else:
                break
        header = ''.join(header_lines)

    with open(EXEMPT_FILE, "w") as f:
        f.write(header)
        for entry in entries:
            f.write(entry + '\n')


def cmd_list():
    entries = read_exemptions()
    classes = [e for e in entries if not e.startswith('title:')]
    titles = [e.removeprefix('title:') for e in entries if e.startswith('title:')]

    print("Class Exemptions:")
    for i, p in enumerate(classes, 1):
        print(f"  {i}. {p}")

    print("\nTitle Exemptions:")
    for i, p in enumerate(titles, 1):
        print(f"  {i}. {p}")


def toggle_entry(pattern, is_title=False):
    """Add or remove a pattern from the exemption list."""
    entries = read_exemptions()
    escaped = escape_for_regex(pattern)

    if is_title:
        key = f"title:{escaped}"
        display = f"title '{pattern}'"
    else:
        key = escaped
        display = f"class '{pattern}'"

    # Check if already exempt (match escaped or raw)
    found = None
    for entry in entries:
        raw = entry.removeprefix('title:') if is_title else entry
        if raw == escaped or raw == pattern:
            found = entry
            break

    if found:
        entries.remove(found)
        write_exemptions(entries)
        notify(f"Removed exemption for {display}")
    else:
        entries.append(key)
        write_exemptions(entries)
        notify(f"Exempted {display} from forced size")


def main():
    args = sys.argv[1:]

    if not args:
        cls, title = get_active_window_info()
        if not cls:
            notify("No active window found")
            sys.exit(1)
        toggle_entry(cls, is_title=False)

    elif args[0] == "--title":
        cls, title = get_active_window_info()
        if not title:
            notify("No active window title found")
            sys.exit(1)
        toggle_entry(title, is_title=True)

    elif args[0] == "--list":
        cmd_list()

    elif args[0] in ("--help", "-h"):
        print(__doc__.strip())

    else:
        toggle_entry(args[0], is_title=False)


if __name__ == "__main__":
    main()
