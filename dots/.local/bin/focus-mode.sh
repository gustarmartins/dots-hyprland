#!/bin/bash
# kate: mode syntax Bash;
set -euo pipefail

APPLY=/usr/local/bin/focus-mode-apply
DMA_UNIT=focus-dma-latency
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/focus-mode"

is_on() {
    systemctl is-active --quiet "$DMA_UNIT" &&
        [ -f "/run/focus-mode/enabled-$UID" ]
}

active_pid() {
    hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty'
}

active_kind() {
    hyprctl activewindow -j 2>/dev/null | jq -r '
        if ((.contentType // "") == "game")
           or ((.class // "") | test("eden|yuzu|suyu|Ryujinx|Cemu|steam|lutris|heroic|osu"; "i"))
        then "game" else "app" end
    '
}

turn_on() {
    local pid kind
    pid=$(active_pid)
    kind=$(active_kind)
    sudo -n "$APPLY" on
    [ -n "$pid" ] && sudo -n "$APPLY" focus "$pid" "$kind"
}

turn_off() {
    sudo -n "$APPLY" off
    rm -rf "$STATE_DIR"
}

show_status() {
    printf 'mode=%s\n' "$(is_on && echo on || echo off)"
    printf 'selector=%s\n' "$(active_pid) $(active_kind)"
    printf 'hypr_active=%s\n' "$(hyprctl activewindow -j 2>/dev/null | jq -r '"\(.pid // 0) \(.class // "none")"')"
    sudo -n "$APPLY" status
}

case "${1:-}" in
    get_state) is_on && echo on || echo off ;;
    status)    show_status ;;
    on)        turn_on ;;
    off)       turn_off ;;
    toggle)    is_on && turn_off || turn_on ;;
    *)         echo "usage: focus-mode.sh {get_state|status|on|off|toggle}" >&2; exit 1 ;;
esac
