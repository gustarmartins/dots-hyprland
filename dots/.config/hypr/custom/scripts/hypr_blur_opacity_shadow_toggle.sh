#!/usr/bin/env bash
# Persistently toggle blur, shadow, and opacity in the Lua shell override.

set -o errexit
set -o nounset
set -o pipefail

readonly CONFIG_FILE="${HOME}/.config/hypr/hyprland/shellOverrides/main.lua"
readonly CONFIGURATOR="${HOME}/.config/quickshell/ii/scripts/hyprland/hyprconfigurator.py"
readonly STATE_FILE="${HOME}/.config/dusky/settings/opacity_blur"

readonly OP_ACTIVE_ON="0.8"
readonly OP_INACTIVE_ON="0.6"
readonly OP_ACTIVE_OFF="1.0"
readonly OP_INACTIVE_OFF="1.0"

die() {
    local message="$1"
    printf 'Error: %s\n' "$message" >&2
    if command -v notify-send &>/dev/null; then
        notify-send "Hyprland Error" "$message" 2>/dev/null || true
    fi
    exit 1
}

notify() {
    local message="$1"
    if command -v notify-send &>/dev/null; then
        notify-send \
            -h string:x-canonical-private-synchronous:hypr-visuals \
            -t 1500 \
            "Hyprland" "$message" 2>/dev/null || true
    fi
}

get_current_state() {
    if [[ -f "$STATE_FILE" ]] && grep -qx 'True' "$STATE_FILE"; then
        printf 'on'
    else
        printf 'off'
    fi
}

show_help() {
    cat <<EOF
Usage: ${0##*/} [on|off|toggle]

Persistently control Hyprland blur, shadow, and window opacity through:
  ${CONFIG_FILE}
EOF
}

case "${1:-toggle}" in
    on|ON|enable|1|true|yes) TARGET_STATE="on" ;;
    off|OFF|disable|0|false|no) TARGET_STATE="off" ;;
    toggle|"")
        if [[ "$(get_current_state)" == "on" ]]; then
            TARGET_STATE="off"
        else
            TARGET_STATE="on"
        fi
        ;;
    -h|--help|help) show_help; exit 0 ;;
    *) printf 'Unknown argument: %s\n\n' "$1" >&2; show_help >&2; exit 1 ;;
esac

[[ -f "$CONFIGURATOR" ]] || die "Lua configurator not found: $CONFIGURATOR"
command -v python3 &>/dev/null || die "python3 not found"
command -v hyprctl &>/dev/null || die "hyprctl not found in PATH"

if [[ "$TARGET_STATE" == "on" ]]; then
    NEW_ENABLED="true"
    NEW_ACTIVE="$OP_ACTIVE_ON"
    NEW_INACTIVE="$OP_INACTIVE_ON"
    NOTIFY_MSG="Visuals: Max (Blur/Shadow ON)"
    STATE_STRING="True"
else
    NEW_ENABLED="false"
    NEW_ACTIVE="$OP_ACTIVE_OFF"
    NEW_INACTIVE="$OP_INACTIVE_OFF"
    NOTIFY_MSG="Visuals: Performance (Blur/Shadow OFF)"
    STATE_STRING="False"
fi

mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$STATE_FILE")"

python3 "$CONFIGURATOR" \
    --file "$CONFIG_FILE" \
    --set decoration:blur:enabled "$NEW_ENABLED" \
    --set decoration:shadow:enabled "$NEW_ENABLED" \
    --set decoration:active_opacity "$NEW_ACTIVE" \
    --set decoration:inactive_opacity "$NEW_INACTIVE" \
    >/dev/null || die "Failed to update Lua shell overrides"

printf '%s' "$STATE_STRING" > "$STATE_FILE"

# The override file is part of the Lua dependency graph; reload is the safe
# way to apply all four persistent values together.
if ! hyprctl reload &>/dev/null; then
    die "Lua overrides were saved, but Hyprland reload failed"
fi

notify "$NOTIFY_MSG"
