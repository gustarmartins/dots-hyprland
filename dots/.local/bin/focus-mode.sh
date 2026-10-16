#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    get_state)
        if [[ -f /run/focus-mode/enabled-$UID ]]; then echo on; else echo off; fi
        ;;
    on|off|toggle|status|hardware-on|hardware-off)
        exec sudo -n /usr/local/bin/focus-mode-apply "$1"
        ;;
    *) echo 'usage: focus-mode.sh {on|off|toggle|status|hardware-on|hardware-off|get_state}' >&2; exit 2 ;;
esac
