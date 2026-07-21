#!/bin/bash
set -euo pipefail

APPLY=/usr/local/bin/focus-mode-apply
WATCH=/home/gus/.local/bin/focus-mode-watch
WATCH_UNIT=focus-mode-watch.service
DMA_UNIT=focus-dma-latency
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/focus-mode"
WATCH_PID="$STATE_DIR/watch.pid"
LEGACY_WATCH_PID="${XDG_RUNTIME_DIR:-/tmp}/focus-mode-watch.pid"

is_on() {
    systemctl is-active --quiet "$DMA_UNIT" &&
        systemctl --user is-active --quiet "$WATCH_UNIT"
}

watch_pid_is_valid() {
    local pid=${1:-} cmdline
    [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] || return 1
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    [[ "$cmdline" == *"$WATCH"* ]]
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

start_watch() {
    mkdir -p "$STATE_DIR"
    if [ -f "$LEGACY_WATCH_PID" ] && watch_pid_is_valid "$(cat "$LEGACY_WATCH_PID" 2>/dev/null)"; then
        kill "$(cat "$LEGACY_WATCH_PID" 2>/dev/null)" 2>/dev/null || true
        rm -f "$LEGACY_WATCH_PID"
    fi
    if [ -f "$WATCH_PID" ] && watch_pid_is_valid "$(cat "$WATCH_PID" 2>/dev/null)"; then
        kill "$(cat "$WATCH_PID" 2>/dev/null)" 2>/dev/null || true
    fi
    rm -f "$WATCH_PID"
    systemctl --user start "$WATCH_UNIT"
}

stop_watch() {
    systemctl --user stop "$WATCH_UNIT" 2>/dev/null || true
    for pidfile in "$WATCH_PID" "$LEGACY_WATCH_PID"; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile" 2>/dev/null || true)
        watch_pid_is_valid "$pid" && kill "$pid" 2>/dev/null || true
        rm -f "$pidfile"
    done
}

turn_on() {
    start_watch
    sudo -n "$APPLY" on
}

turn_off() {
    sudo -n "$APPLY" off
    rm -rf "$STATE_DIR"
}

show_status() {
    printf 'mode=%s\n' "$(is_on && echo on || echo off)"
    printf 'selector=%s\n' "$("$WATCH" select 2>/dev/null || echo unavailable)"
    printf 'hypr_active=%s\n' "$(hyprctl activewindow -j 2>/dev/null | jq -r '"\(.pid // 0) \(.class // "none")"')"
    systemctl --user show "$WATCH_UNIT" \
        -p ActiveState -p SubState -p MainPID -p NRestarts --no-pager
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
