#!/usr/bin/env bash
# kate: mode syntax Bash;
# Driver for the QS Memory tile: read-only snapshot on left-click and a
# separate, low-priority NVMe RAM Plus tier on literal right-click.
set -euo pipefail

RAM_PLUS=/var/lib/ram-plus.swap
HELPER=/usr/local/bin/memory-tool-apply

get_state() {
    if awk -v dev="$RAM_PLUS" '$1 == dev {found=1} END {exit !found}' /proc/swaps; then
        echo ram-plus
    else
        echo off
    fi
}

report() {
    local atlas scope body
    atlas=$(NO_COLOR=1 "$HOME/.local/bin/vmatlas" 2>&1)
    scope=$(NO_COLOR=1 "$HOME/.local/bin/vmscope" 2>&1)
    body="$atlas

$scope"
    notify-send -a "Memory Tools" -u normal -t 30000 \
        "Memory / VM snapshot" "$body" >/dev/null 2>&1 || true
    printf '%s\n' "$body"
}

toggle_ram_plus() {
    local out rc
    set +e
    out=$(sudo -n "$HELPER" ram-plus toggle 2>&1)
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        notify-send -a "Memory Tools" -t 10000 "RAM Plus" "$out" >/dev/null 2>&1 || true
    else
        notify-send -a "Memory Tools" -u critical -t 15000 "RAM Plus failed" "$out" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$out"
    return "$rc"
}

case "${1:-}" in
    get_state|status) get_state ;;
    report) report ;;
    toggle) toggle_ram_plus ;;
    on|off)
        sudo -n "$HELPER" ram-plus "$1"
        ;;
    *) echo "usage: $0 {get_state|report|toggle|on|off}" >&2; exit 2 ;;
esac
