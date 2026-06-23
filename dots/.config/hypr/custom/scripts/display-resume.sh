#!/usr/bin/env bash
[ -n "$1" ] && sleep "$1"

sig=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/" 2>/dev/null | head -n1)
[ -n "$sig" ] || exit 0
export HYPRLAND_INSTANCE_SIGNATURE="$sig"

conf="$HOME/.config/hypr/monitors.conf"
[ -r "$conf" ] || exit 0

while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    val="${line#monitor = }"
    [ "$val" = "$line" ] && val="${line#monitor=}"
    [ "$val" = "$line" ] && continue
    hyprctl keyword monitor "$val"
done < "$conf"
