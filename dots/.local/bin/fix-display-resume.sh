#!/bin/bash
# Fix display state after sleep/suspend/DPMS-off by re-applying the
# declarative Lua monitor profiles.

sleep 2

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$runtime_dir"
export HYPRLAND_INSTANCE_SIGNATURE
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$runtime_dir/hypr/" 2>/dev/null | head -n1)
SOCK="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"

if [ ! -S "$SOCK" ]; then
    echo "fix-display-resume: Hyprland socket not found, aborting" >&2
    exit 1
fi

echo "fix-display-resume: re-applying Lua monitor profiles"
hyprctl eval 'local monitors = require("monitors"); hl.monitor(monitors.aoc); hl.monitor(monitors.arzopa)'
