#!/usr/bin/env python3
"""
Exempt a window class from the master_float forced size.

Usage:
  exempt-float-size.py              Toggles exemption for the currently focused window
  exempt-float-size.py <class>      Exempts a specific window class
  exempt-float-size.py --list       Shows all currently exempted classes
  exempt-float-size.py --remove     Removes exemption for the focused window
  exempt-float-size.py --remove <class>  Removes exemption for a specific class
"""

import sys
import os
import re
import json
import subprocess

RULES_FILE = os.path.expanduser("~/.config/hypr/custom/rules.conf")

# ── helpers ──────────────────────────────────────────────────────────

def notify(msg):
    subprocess.run(["notify-send", "Float Exempt", msg])

def get_active_class():
    result = subprocess.run(
        ["hyprctl", "activewindow", "-j"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
        return data.get("class") or None
    except json.JSONDecodeError:
        return None

def escape_for_re2(s):
    """Escape special regex characters for Hyprland's RE2 engine."""
    return re.sub(r'([.\\+*?^$\[\]{}()|])', r'\\\1', s)

def read_rules():
    with open(RULES_FILE, "r") as f:
        return f.read()

def write_rules(content):
    with open(RULES_FILE, "w") as f:
        f.write(content)

def get_exempt_list(content):
    """Parse the current negative regex and return the list of exempted patterns."""
    match = re.search(r'negative:\^\((.+?)\)\$', content)
    if not match:
        return []
    return match.group(1).split("|")

# ── commands ─────────────────────────────────────────────────────────

def cmd_list():
    content = read_rules()
    exemptions = get_exempt_list(content)
    if not exemptions:
        print("No exemptions found.")
        return
    print("Currently exempted from forced float size:")
    for i, pattern in enumerate(exemptions, 1):
        print(f"  {i}. {pattern}")

def cmd_add(raw_class):
    escaped = escape_for_re2(raw_class)
    content = read_rules()
    exemptions = get_exempt_list(content)

    # Check if already present (compare against both raw and escaped)
    for ex in exemptions:
        if ex == escaped or ex == raw_class:
            notify(f"'{raw_class}' is already exempted")
            print(f"'{raw_class}' is already exempted.")
            return

    # Insert the new class into the negative regex: before the )$
    pattern = r'(negative:\^\()(.*?)(\)\$)'
    replacement = rf'\g<1>\g<2>|{escaped}\g<3>'
    new_content = re.sub(pattern, replacement, content, count=1)

    if new_content == content:
        notify("Could not find master_float_size rule")
        print("Error: Could not find master_float_size rule in rules.conf")
        sys.exit(1)

    write_rules(new_content)
    subprocess.run(["hyprctl", "reload"])
    notify(f"Exempted '{raw_class}'")
    print(f"Exempted '{raw_class}' from forced float size.")

def cmd_remove(raw_class):
    escaped = escape_for_re2(raw_class)
    content = read_rules()
    exemptions = get_exempt_list(content)

    # Find and remove the matching entry
    to_remove = None
    for ex in exemptions:
        if ex == escaped or ex == raw_class:
            to_remove = ex
            break

    if to_remove is None:
        notify(f"'{raw_class}' is not in the exemption list")
        print(f"'{raw_class}' is not in the exemption list.")
        return

    if len(exemptions) <= 1:
        notify("Cannot remove the last exemption — at least one must remain")
        print("Error: Cannot remove the last exemption.")
        sys.exit(1)

    exemptions.remove(to_remove)
    new_regex = f"negative:^({'|'.join(exemptions)})$"

    # Replace the old negative regex with the new one
    pattern = r'negative:\^\(.+?\)\$'
    new_content = re.sub(pattern, new_regex, content, count=1)

    write_rules(new_content)
    subprocess.run(["hyprctl", "reload"])
    notify(f"Removed exemption for '{raw_class}'")
    print(f"Removed exemption for '{raw_class}'.")

def cmd_toggle(raw_class):
    escaped = escape_for_re2(raw_class)
    content = read_rules()
    exemptions = get_exempt_list(content)

    for ex in exemptions:
        if ex == escaped or ex == raw_class:
            # Already exempted, so remove it
            cmd_remove(raw_class)
            return
            
    # Not exempted, so add it
    cmd_add(raw_class)

# ── main ─────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        # No args: toggle exemption for the focused window
        cls = get_active_class()
        if not cls:
            notify("No active window found")
            sys.exit(1)
        cmd_toggle(cls)

    elif args[0] == "--list":
        cmd_list()

    elif args[0] == "--remove":
        if len(args) > 1:
            cmd_remove(args[1])
        else:
            cls = get_active_class()
            if not cls:
                notify("No active window found")
                sys.exit(1)
            cmd_remove(cls)

    elif args[0] in ("--help", "-h"):
        print(__doc__.strip())

    else:
        cmd_add(args[0])

if __name__ == "__main__":
    main()
