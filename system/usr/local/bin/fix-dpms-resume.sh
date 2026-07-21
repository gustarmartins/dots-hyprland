#!/bin/bash
# Quick monitor config re-apply for DPMS on-resume (no sleep needed)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /tmp/hypr/ 2>/dev/null | head -n1)
CONF="/home/gus/.config/hypr/monitors.conf"
while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    val="${line#monitor = }"
    [ "$val" = "$line" ] && val="${line#monitor=}"
    [ "$val" = "$line" ] && continue
    hyprctl keyword monitor "$val"
done < "$CONF"
