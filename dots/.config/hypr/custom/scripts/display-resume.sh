#!/usr/bin/env bash
[ -n "$1" ] && sleep "$1"

sig=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/" 2>/dev/null | head -n1)
[ -n "$sig" ] || exit 0
export HYPRLAND_INSTANCE_SIGNATURE="$sig"

hyprctl eval 'local monitors = require("monitors"); hl.monitor(monitors.aoc); hl.monitor(monitors.arzopa)'
