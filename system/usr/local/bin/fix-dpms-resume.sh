#!/bin/bash
# Quick Lua monitor profile re-apply for DPMS on-resume (no sleep needed)
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$runtime_dir"
export HYPRLAND_INSTANCE_SIGNATURE
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$runtime_dir/hypr/" 2>/dev/null | head -n1)
hyprctl eval 'local monitors = require("monitors"); hl.monitor(monitors.aoc); hl.monitor(monitors.arzopa)'
