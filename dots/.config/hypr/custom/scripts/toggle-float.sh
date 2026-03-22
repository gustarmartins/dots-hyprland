#!/usr/bin/env bash

STATE_FILE="/tmp/hypr_master_float_state"

if [ -f "$STATE_FILE" ]; then
    rm "$STATE_FILE"
    # Disable both master float rules
    hyprctl --batch "\
        keyword 'windowrule[master_float]:enable false' ; \
        keyword 'windowrule[master_float_size]:enable false'"

    # Unfloat all windows that were forced to float on the active workspace
    ACTIVE_WS=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl clients -j | jq -r \
        --argjson ws "$ACTIVE_WS" \
        '.[] | select(.workspace.id == $ws and .floating == true) | .address' \
    | while read -r addr; do
        hyprctl dispatch settiled "address:$addr"
    done

    notify-send "Hyprland" "Master Float: OFF (Normal Mode)"
else
    touch "$STATE_FILE"
    # Enable both master float rules
    hyprctl --batch "\
        keyword 'windowrule[master_float]:enable true' ; \
        keyword 'windowrule[master_float_size]:enable true'"

    # Float all existing windows on the active workspace
    ACTIVE_WS=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl clients -j | jq -r \
        --argjson ws "$ACTIVE_WS" \
        '.[] | select(.workspace.id == $ws and .floating == false) | .address' \
    | while read -r addr; do
        hyprctl dispatch setfloating "address:$addr"
    done

    notify-send "Hyprland" "Master Float: ON (All new windows float)"
fi
