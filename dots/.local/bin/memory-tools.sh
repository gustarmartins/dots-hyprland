#!/usr/bin/env bash
# kate: mode syntax Bash;
# User-facing notification/status driver for Quickshell memory action tiles.
set -euo pipefail

ROOT_HELPER=/usr/local/bin/memory-tool-apply
MODE_DIR="$HOME/.config/memory-tools"
MODE_FILE="$MODE_DIR/recompress-mode"
ZRAM=/sys/block/zram0

notify() {
    local title=$1 body=$2 urgency=${3:-normal}
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "Memory Tools" -u "$urgency" -t 20000 "$title" "$body" >/dev/null 2>&1 || true
}

run_root() {
    local title=$1
    shift
    local out rc
    set +e
    out=$(sudo -n "$ROOT_HELPER" "$@" 2>&1)
    rc=$?
    set -e
    printf '%s\n' "$out"
    if [ "$rc" -eq 0 ]; then
        notify "$title" "$out"
    else
        notify "$title failed" "$out" critical
    fi
    return "$rc"
}

recompress_mode() {
    local mode
    mode=$(cat "$MODE_FILE" 2>/dev/null || true)
    case "$mode" in idle|huge-idle|huge|all) echo "$mode" ;; *) echo idle ;; esac
}

recompress_cycle() {
    local current next
    current=$(recompress_mode)
    case "$current" in
        idle) next=huge-idle ;;
        huge-idle) next=huge ;;
        huge) next=all ;;
        all) next=idle ;;
    esac
    mkdir -p "$MODE_DIR"
    printf '%s\n' "$next" >"$MODE_FILE"
    notify "ZRAM recompression mode" "Selected: $next. Left-click Recompress to run it."
    echo "$next"
}

writeback_status() {
    local enabled pages written cap_pages remaining
    cap_pages=$((4 * 1024 * 1024 * 1024 / 4096))
    enabled=$(cat "$ZRAM/writeback_limit_enable" 2>/dev/null || echo 0)
    pages=$(cat "$ZRAM/writeback_limit" 2>/dev/null || echo 0)
    written=$(awk '{print $3}' "$ZRAM/bd_stat" 2>/dev/null || echo 0)
    case "$pages" in ''|*[!0-9]*) pages=0 ;; esac
    case "$written" in ''|*[!0-9]*) written=0 ;; esac
    if [ "$enabled" != 1 ]; then
        echo "Unsafe: unlimited"
    elif [ "$written" -ge "$cap_pages" ]; then
        awk -v p="$written" 'BEGIN {printf "Cap reached · %.1f GiB written\n", p*4096/1073741824}'
    elif [ "$pages" -gt 0 ]; then
        awk -v p="$pages" 'BEGIN {printf "Pass active · %.0f MiB left\n", p*4096/1048576}'
    else
        remaining=$((cap_pages - written))
        awk -v p="$remaining" 'BEGIN {printf "Guarded · %.1f GiB boot quota\n", p*4096/1073741824}'
    fi
}

gpu_short() {
    local card=/sys/class/drm/card1/device used total busy
    [ -r "$card/mem_info_vram_used" ] || { echo "Unavailable"; return; }
    used=$(cat "$card/mem_info_vram_used")
    total=$(cat "$card/mem_info_vram_total")
    busy=$(cat "$card/gpu_busy_percent")
    awk -v u="$used" -v t="$total" -v b="$busy" \
        'BEGIN {printf "%.0f%% VRAM · %d%% GPU\n", (t ? u*100/t : 0), b}'
}

gpu_report() {
    local card=/sys/class/drm/card1/device body perf
    perf=$(cat "$card/power_dpm_force_performance_level" 2>/dev/null || echo unknown)
    body="$(gpu_short)
Performance level: $perf
VRAM: $(awk '{printf "%.2f", $1/1073741824}' "$card/mem_info_vram_used") / $(awk '{printf "%.2f", $1/1073741824}' "$card/mem_info_vram_total") GiB
PCIe: $(cat "$card/current_link_speed" 2>/dev/null || echo '?') x$(cat "$card/current_link_width" 2>/dev/null || echo '?')"
    notify "AMDGPU memory" "$body"
    printf '%s\n' "$body"
}

case "${1:-}" in
    recompress-status) recompress_mode ;;
    recompress-cycle) recompress_cycle ;;
    recompress-run) run_root "ZRAM recompression" recompress "$(recompress_mode)" ;;
    writeback-status) writeback_status ;;
    writeback-cold) run_root "ZRAM cold-page writeback" writeback cold ;;
    writeback-all)
        if [ "${2:-}" != "CONFIRM-DRAIN-ALL" ]; then
            msg="Refused: full ZRAM-to-NVMe drain requires an explicit terminal confirmation. Run: $0 writeback-all CONFIRM-DRAIN-ALL"
            notify "ZRAM emergency writeback blocked" "$msg" critical
            printf '%s\n' "$msg" >&2
            exit 64
        fi
        run_root "ZRAM emergency writeback" writeback all
        ;;
    drop-caches) run_root "Drop caches" drop-caches ;;
    compact-memory) run_root "Physical memory compaction" compact-memory ;;
    compact-zram) run_root "ZRAM allocator compaction" compact-zram ;;
    gpu-status) gpu_short ;;
    gpu-report) gpu_report ;;
    gpu-evict) run_root "AMDGPU VRAM eviction" gpu-evict ;;
    *)
        echo "usage: memory-tools.sh {recompress-status|recompress-cycle|recompress-run|writeback-status|writeback-cold|writeback-all CONFIRM-DRAIN-ALL|drop-caches|compact-memory|compact-zram|gpu-status|gpu-report|gpu-evict}" >&2
        exit 2
        ;;
esac
