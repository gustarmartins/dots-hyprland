#!/usr/bin/env bash
#
# Save focused window geometry PER-APP (class-only key)
# Usage: Super+Ctrl+F11
#
# Saves geometry using just the class name — applies to ALL windows
# of this app equally. Use per-window save (Ctrl+F12) when you need
# different sizes for different windows of the same app.
# Lookup priority in the listener: class::title > class (this one).
#
# Coordinates are saved MONITOR-RELATIVE so windows restore to
# whichever monitor the cursor is on, not the original monitor.

FILE="$HOME/.config/hypr/custom/autofloat_positions.json"
[ ! -f "$FILE" ] && echo "{}" > "$FILE"

active=$(hyprctl activewindow -j)
cls=$(echo "$active" | jq -r '.class')

if [ -z "$cls" ] || [ "$cls" == "null" ]; then
    notify-send "Float Error" "No active window found."
    exit 1
fi

key="$cls"
exists=$(jq -r --arg k "$key" 'has($k)' "$FILE")

if [ "$exists" == "true" ]; then
    tmp=$(mktemp)
    jq --arg k "$key" 'del(.[$k])' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    notify-send "Float Position" "🗑 Removed per-app geometry for '${cls}'"
else
    w=$(echo "$active" | jq -r '.size[0]')
    h=$(echo "$active" | jq -r '.size[1]')
    gx=$(echo "$active" | jq -r '.at[0]')
    gy=$(echo "$active" | jq -r '.at[1]')
    mon_id=$(echo "$active" | jq -r '.monitor')

    # Get monitor offset to convert global → monitor-relative
    mon_info=$(hyprctl monitors -j | jq -r --argjson id "$mon_id" \
        '.[] | select(.id == $id) | "\(.x) \(.y)"')
    read -r mon_x mon_y <<< "$mon_info"
    : "${mon_x:=0}" "${mon_y:=0}"

    x=$((gx - mon_x))
    y=$((gy - mon_y))

    tmp=$(mktemp)
    jq --arg k "$key" \
       --argjson w "$w" --argjson h "$h" --argjson x "$x" --argjson y "$y" \
       '.[$k] = {"w": $w, "h": $h, "x": $x, "y": $y}' "$FILE" > "$tmp" && mv "$tmp" "$FILE"

    notify-send "Float Position" "📦 Saved per-app geometry for '${cls}': ${w}×${h} at ${x},${y} (monitor-relative)"
fi
