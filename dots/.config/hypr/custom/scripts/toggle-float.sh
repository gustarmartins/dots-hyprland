#!/usr/bin/env bash
#
# Master Float Toggle
# Super+F11: Toggle floating ALL new windows automatically
#
# Works independently of Geometry Restore (Super+F10).
# Starts the IPC daemon when needed, stops it when no features are active.
#
# When ON:  all new windows float at 1200×800 centered (unless exempt)
# When OFF: unfloats all windows on current workspace

STATE_FILE="/tmp/hypr_master_float_state"
GEO_RESTORE_FILE="$HOME/.config/hypr/custom/.geo_restore_enabled"
GEO_DAEMON_SCRIPT="$HOME/.config/hypr/custom/scripts/geo-daemon.sh"

if [ -f "$STATE_FILE" ]; then
    # --- TURN OFF ---
    rm -f "$STATE_FILE"

    # Unfloat all windows on the active workspace
    ACTIVE_WS=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl clients -j | jq -r \
        --argjson ws "$ACTIVE_WS" \
        '.[] | select(.workspace.id == $ws and .floating == true) | .address' \
    | while read -r addr; do
        hyprctl dispatch "hl.dsp.window.float({ action = \"disable\", window = \"address:$addr\" })"
    done

    # Stop the daemon if geometry restore is also off
    bash "$GEO_DAEMON_SCRIPT" --stop
    # Re-start only if geometry restore still needs it
    if [ -f "$GEO_RESTORE_FILE" ]; then
        bash "$GEO_DAEMON_SCRIPT" --ensure
    fi

    notify-send "Hyprland" "Master Float: OFF"
else
    # --- TURN ON ---
    touch "$STATE_FILE"

    # Ensure the IPC daemon is running
    bash "$GEO_DAEMON_SCRIPT" --ensure

    # Float all existing windows on the active workspace
    ACTIVE_WS=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl clients -j | jq -r \
        --argjson ws "$ACTIVE_WS" \
        '.[] | select(.workspace.id == $ws and .floating == false) | .address' \
    | while read -r addr; do
        hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$addr\" })"
    done

    notify-send "Hyprland" "Master Float: ON"
fi
