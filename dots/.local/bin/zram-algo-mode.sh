#!/bin/bash
# kate: mode syntax Bash;
# zram-algo-mode.sh {status|live|staged|next|set <zstd|lz4|lz4hc>}
# User-level driver for the QS "ZRAM Algo" toggle.
set -euo pipefail

STAGE=/usr/local/bin/zram-profile-stage
LIVE=/usr/local/bin/zram-algo-live
CONF=/etc/systemd/zram-generator.conf
CYCLE=(zstd lz4 lz4hc)

selected() {
    awk '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^\[/ && $i ~ /\]$/) {
                gsub(/[\[\]]/, "", $i)
                print $i
                exit
            }
        }
    }' /sys/block/zram0/comp_algorithm 2>/dev/null
}

staged() {
    awk -F= '/^[[:space:]]*compression-algorithm[[:space:]]*=/ {
        v=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        split(v, a, /[[:space:]]+/)
        print a[1]
        exit
    }' "$CONF" 2>/dev/null
}

notify_result() {
    local title=$1
    shift
    local out rc
    set +e
    out=$("$@" 2>&1)
    rc=$?
    set -e
    printf '%s\n' "$out"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -t 8000 "$title" "$out" >/dev/null 2>&1 || true
    fi
    return "$rc"
}

next_algo() {
    local cur i
    cur=$(staged)
    [ -n "$cur" ] || cur=$(selected)
    for i in "${!CYCLE[@]}"; do
        if [ "${CYCLE[$i]}" = "$cur" ]; then
            echo "${CYCLE[$(( (i + 1) % ${#CYCLE[@]} ))]}"
            return
        fi
    done
    echo zstd
}

case "${1:-}" in
    live)
        target=$(staged)
        [ -n "$target" ] || target=zstd
        notify_result "ZRAM live algorithm" sudo -n "$LIVE" "$target"
        ;;
    staged)
        staged
        ;;
    status|get_state)
        live=$(selected)
        next=$(staged)
        [ -n "$live" ] || live=unknown
        [ -n "$next" ] || next=unknown
        if [ "$live" = "$next" ]; then
            echo "$live"
        else
            echo "$live->$next"
        fi
        ;;
    next|toggle)
        target=$(next_algo)
        notify_result "ZRAM staged algorithm" sudo -n "$STAGE" algo "$target"
        ;;
    set)
        case "${2:-}" in
            zstd|lz4|lz4hc) notify_result "ZRAM staged algorithm" sudo -n "$STAGE" algo "$2" ;;
            *) echo "usage: $0 set <zstd|lz4|lz4hc>" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "usage: $0 {status|live|staged|next|set <zstd|lz4|lz4hc>}" >&2
        exit 1
        ;;
esac
