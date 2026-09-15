#!/usr/bin/env bash
set -euo pipefail

ROOT_HELPER=/usr/local/bin/memory-tool-apply
ZRAM=/sys/block/zram0
STATE_DIR=/run/vmatlas-tier
EVENT_LOG=$STATE_DIR/events
WB_STATE=$STATE_DIR/writeback_pages
TIER_CONF=/etc/vmatlas/zram-tiers.conf
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/memory-tools"
MODE_FILE="$MODE_DIR/recompress-mode"
CARD=/sys/class/drm/card1/device
PAGE=4096

RENDER=auto
for a in "$@"; do
    case "$a" in
        --report) RENDER=report ;;
        --oneline) RENDER=oneline ;;
        --no-color) NO_COLOR=1 ;;
    esac
done
ARGS=()
for a in "$@"; do
    case "$a" in --report|--oneline|--no-color) ;; *) ARGS+=("$a") ;; esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    R=$'\e[0m'; B=$'\e[1m'; D=$'\e[2m'
    RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; CYN=$'\e[36m'; W=$'\e[97m'
    IS_TTY=1
else
    R=''; B=''; D=''; RED=''; GRN=''; YLW=''; CYN=''; W=''
    IS_TTY=0
fi
[ "$RENDER" != auto ] || { [ "$IS_TTY" = 1 ] && RENDER=report || RENDER=oneline; }

hb() {
    awk -v b="${1:-0}" 'BEGIN{
        s=""; if (b<0) { s="-"; b=-b }
        split("B KiB MiB GiB TiB PiB", u, " "); i=1
        while (b >= 1024 && i < 6) { b /= 1024; i++ }
        if (i == 1) printf "%s%d %s", s, b, u[i]; else printf "%s%.1f %s", s, b, u[i]
    }'
}
hpg() { hb $(( ${1:-0} * PAGE )); }
num() { printf '%s' "${1:-0}"; }

delta_cost() {
    local d=${1:-0}
    if [ "$d" -gt 0 ]; then printf '%s+%s%s' "$YLW" "$(hb "$d")" "$R"
    elif [ "$d" -lt 0 ]; then printf '%s%s%s' "$GRN" "$(hb "$d")" "$R"
    else printf '%s0 B%s' "$D" "$R"; fi
}
delta_mem() {
    local d=${1:-0}
    if [ "$d" -lt 0 ]; then printf '%s%s%s' "$GRN" "$(hb "$d")" "$R"
    elif [ "$d" -gt 0 ]; then printf '%s+%s%s' "$RED" "$(hb "$d")" "$R"
    else printf '%s0 B%s' "$D" "$R"; fi
}

bar() {
    local used=${1:-0} total=${2:-1} width=${3:-20} pct filled i out c
    [ "$total" -gt 0 ] || total=1
    pct=$(( used * 100 / total ))
    [ "$pct" -le 100 ] || pct=100
    [ "$pct" -ge 0 ] || pct=0
    filled=$(( pct * width / 100 ))
    c=$GRN; [ "$pct" -lt 60 ] || c=$YLW; [ "$pct" -lt 90 ] || c=$RED
    out=''; for ((i=0;i<filled;i++)); do out+='█'; done
    printf '%s%s%s' "$c" "$out" "$D"
    out=''; for ((i=filled;i<width;i++)); do out+='░'; done
    printf '%s%s  %s%d%%%s' "$out" "$R" "$W" "$pct" "$R"
}

hdr() { printf '\n%s%s▸ %s%s\n\n' "$B" "$CYN" "$1" "$R"; }
row() { printf '  %s%-19s%s %s\n' "$D" "$1" "$R" "$2"; }
note() { printf '  %s%s%s\n' "$D" "$1" "$R"; }

dur() {
    local s=${1:-0}
    if [ "$s" -ge 86400 ]; then awk -v s="$s" 'BEGIN{printf "%gd", s/86400}'
    elif [ "$s" -ge 3600 ]; then awk -v s="$s" 'BEGIN{printf "%gh", s/3600}'
    elif [ "$s" -ge 60 ]; then printf '%dm' $((s/60))
    else printf '%ds' "$s"; fi
}

conf_get() {
    local key=$1 def=${2:-0} v
    v=$(awk -F= -v k="$key" '$1==k {gsub(/[[:space:]].*$/,"",$2); print $2; exit}' "$TIER_CONF" 2>/dev/null || true)
    case "$v" in ''|*[!0-9]*) printf '%s' "$def" ;; *) printf '%s' "$v" ;; esac
}
conf_str() {
    local key=$1 def=${2:-} v
    v=$(awk -F= -v k="$key" '$1==k {gsub(/[[:space:]].*$/,"",$2); print $2; exit}' "$TIER_CONF" 2>/dev/null || true)
    [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$def"
}

read_mm() {
    MM_ORIG=0 MM_USED=0
    [ -r "$ZRAM/mm_stat" ] || return 0
    read -r MM_ORIG _ MM_USED _ <"$ZRAM/mm_stat" || true
}
read_bd() {
    BD_COUNT=0 BD_READS=0
    [ -r "$ZRAM/bd_stat" ] || return 0
    read -r BD_COUNT BD_READS _ <"$ZRAM/bd_stat" || true
}
boot_written_pages() {
    local raw saved=0
    raw=$(awk '{print $3}' "$ZRAM/bd_stat" 2>/dev/null || echo 0)
    [ -r "$WB_STATE" ] && read -r saved <"$WB_STATE" 2>/dev/null || saved=0
    case "$saved" in ''|*[!0-9]*) saved=0 ;; esac
    case "$raw" in ''|*[!0-9]*) raw=0 ;; esac
    [ "$saved" -ge "$raw" ] && printf '%s' "$saved" || printf '%s' "$raw"
}
pipeline() {
    local p t1 t2 t3
    p=$(conf_str PRIMARY_ALGO lz4)
    t1=$(conf_str TIER1_ALGO zstd):$(conf_str TIER1_LEVEL 3)
    t2=$(conf_str TIER2_ALGO zstd):$(conf_str TIER2_LEVEL 9)
    t3=$(conf_str TIER3_ALGO zstd):$(conf_str TIER3_LEVEL 15)
    printf '%s → %s → %s → %s → NVMe' "$p" "$t1" "$t2" "$t3"
}
recompress_mode() {
    local mode
    mode=$(cat "$MODE_FILE" 2>/dev/null || true)
    case "$mode" in tier1|tier2|tier3) printf '%s\n' "$mode" ;; *) printf 'tier1\n' ;; esac
}

ev() { [ -r "$EVENT_LOG" ] || return 0; cat "$EVENT_LOG"; }
ev_count() { ev | awk -v a="action=$1" -v m="${2:-}" '$0 ~ a && (m=="" || $0 ~ ("mode=" m " ")) {n++} END{print n+0}'; }
ev_last() { ev | awk -v a="action=$1" -v m="${2:-}" '$0 ~ a && (m=="" || $0 ~ ("mode=" m " ")) {for(i=1;i<=NF;i++) if($i ~ /^ts=/){split($i,x,"="); t=x[2]}} END{print t+0}'; }
ev_sum() {
    ev | awk -v a="action=$1" -v m="${2:-}" -v f1="$3" -v f2="$4" '
        $0 ~ a && (m=="" || $0 ~ ("mode=" m " ")) {
            b=0; e=0
            for(i=1;i<=NF;i++){ split($i,x,"="); if(x[1]==f1) b=x[2]; if(x[1]==f2) e=x[2] }
            d=e-b; if (d>0) s+=d
        } END{print s+0}'
}
hhmm() { [ "${1:-0}" -gt 0 ] && date -d "@$1" +%H:%M 2>/dev/null || printf -- '-'; }

notify() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "Memory Tools" -u "${3:-normal}" -t 20000 "$1" "$2" >/dev/null 2>&1 || true
}

run_root() {
    local title=$1 kind=$2 mode=${3:-}
    shift 3
    local out rc
    set +e
    out=$(sudo -n "$ROOT_HELPER" "$@" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        printf '%s%s failed%s\n' "$RED" "$title" "$R" >&2
        printf '%s\n' "$out" | sed 's/^memory-tool: //' | sed "s/^/  /" >&2
        notify "$title failed" "$out" critical
        return "$rc"
    fi
    case "$kind" in
        writeback)   render_writeback_burst "$title" "$mode" "$out" ;;
        recompress)  render_recompress_burst "$title" "$mode" "$out" ;;
        *)           render_plain "$title" "$out" ;;
    esac
    notify "$title" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
}

render_plain() {
    local title=$1 out=$2
    hdr "$title"
    printf '%s\n' "$out" | sed 's/^memory-tool: WARNING: /warning: /' | sed 's/^/  /'
    printf '\n'
}

render_writeback_burst() {
    local title=$1 mode=$2 out=$3 line bc br bw ac ar aw warn
    line=$(printf '%s' "$out" | sed -n 's/^bd_stat: //p' | tail -1)
    warn=$(printf '%s' "$out" | sed -n 's/^memory-tool: WARNING: //p' | tail -1)
    if [ -z "$line" ]; then render_plain "$title" "$out"; return; fi
    read -r bc br bw _ ac ar aw <<<"$(printf '%s' "$line" | tr -d '>' | tr -s ' ')"
    hdr "ZRAM writeback · $mode"
    row "wrote to NVMe" "${W}$(hpg $((aw-bw)))${R}  ${D}$(num $((aw-bw))) pages${R}"
    row "resident on NVMe" "$(hpg "$bc") → ${W}$(hpg "$ac")${R}   $(delta_cost $(( (ac-bc)*PAGE )))"
    [ "$((ar-br))" -eq 0 ] || row "faulted back" "$(hpg "$ar")   $(delta_cost $(( (ar-br)*PAGE )))"
    local written quota
    written=$(boot_written_pages)
    quota=$(( $(conf_get WRITEBACK_BOOT_QUOTA_MIB 4096) * 1024 * 1024 / PAGE ))
    printf '\n'
    row "boot quota" "$(bar "$written" "$quota")   ${D}$(hpg "$written") of $(hpg "$quota")${R}"
    [ -z "$warn" ] || { printf '\n'; note "warning: $warn"; }
    printf '\n'
}

render_recompress_burst() {
    local title=$1 mode=$2 out=$3 line bc bu ac au
    line=$(printf '%s' "$out" | sed -n 's/^compressed\/allocated bytes: //p' | tail -1)
    if [ -z "$line" ]; then render_plain "$title" "$out"; return; fi
    read -r bc bu _ ac au <<<"$(printf '%s' "$line" | tr -d '>' | tr -s ' ')"
    hdr "ZRAM recompression · $mode"
    row "compressed" "$(hb "$bc") → ${W}$(hb "$ac")${R}   $(delta_mem $((ac-bc)))"
    row "allocated" "$(hb "$bu") → ${W}$(hb "$au")${R}   $(delta_mem $((au-bu)))"
    read_mm
    [ "$MM_USED" -gt 0 ] && row "ratio now" "$(awk -v o="$MM_ORIG" -v u="$MM_USED" 'BEGIN{printf "%.2fx", (u?o/u:0)}')"
    printf '\n'
}

writeback_status() {
    local written quota pct enabled limit
    read_bd
    written=$(boot_written_pages)
    quota=$(( $(conf_get WRITEBACK_BOOT_QUOTA_MIB 4096) * 1024 * 1024 / PAGE ))
    enabled=$(cat "$ZRAM/writeback_limit_enable" 2>/dev/null || echo 0)
    limit=$(cat "$ZRAM/writeback_limit" 2>/dev/null || echo 0)
    case "$limit" in ''|*[!0-9]*) limit=0 ;; esac

    if [ "$RENDER" = oneline ]; then
        if [ "$enabled" != 1 ]; then echo "Unsafe: unlimited"
        elif [ "$written" -ge "$quota" ]; then awk -v p="$written" 'BEGIN{printf "Cap reached · %.1f GiB written\n", p*4096/1073741824}'
        elif [ "$limit" -gt 0 ]; then awk -v p="$limit" 'BEGIN{printf "Pass active · %.0f MiB left\n", p*4096/1048576}'
        else awk -v p="$((quota-written))" 'BEGIN{printf "Guarded · %.1f GiB boot quota\n", p*4096/1073741824}'; fi
        return
    fi

    hdr "ZRAM writeback · this boot"
    row "written this boot" "$(bar "$written" "$quota")   ${W}$(hpg "$written")${R} ${D}of $(hpg "$quota") quota${R}"
    row "resident on NVMe" "${W}$(hpg "$BD_COUNT")${R}   ${D}still parked there, $(num "$BD_COUNT") pages${R}"
    row "faulted back" "$(hpg "$BD_READS")   ${D}read from NVMe into RAM${R}"
    if [ "$enabled" != 1 ]; then
        row "guard" "${RED}unlimited${R}"
    elif [ "$limit" -gt 0 ]; then
        row "guard" "${YLW}pass active${R}  ${D}$(hpg "$limit") left${R}"
    else
        row "guard" "${GRN}armed${R}  ${D}$(conf_get WRITEBACK_PASS_MIB 256) MiB per pass${R}"
    fi

    local n
    n=$(ev_count writeback)
    printf '\n'
    if [ "$n" -eq 0 ]; then
        if [ "$written" -gt 0 ]; then
            note "no bursts recorded since the event ledger started"
        else
            note "no writeback this boot"
        fi
    else
        row "bursts" "${W}$n${R}   ${D}last $(hhmm "$(ev_last writeback)")${R}"
        printf '\n'
        printf '  %s%-18s %6s  %12s%s\n' "$D" "mode" "runs" "written" "$R"
        local m c s
        for m in cold idle huge huge-idle incompressible all; do
            c=$(ev_count writeback "$m")
            [ "$c" -gt 0 ] || continue
            s=$(ev_sum writeback "$m" before_writes after_writes)
            printf '  %-18s %6s  %12s\n' "$m" "$c" "$(hpg "$s")"
        done
    fi
    printf '\n'
}

recompress_status() {
    local mode
    mode=$(recompress_mode)
    if [ "$RENDER" = oneline ]; then printf '%s\n' "$mode"; return; fi

    read_mm
    hdr "ZRAM recompression · this boot"
    row "pipeline" "$(pipeline)"
    row "manual tier" "${W}$mode${R}  ${D}$(conf_str "${mode^^}_ALGO" zstd):$(conf_str "${mode^^}_LEVEL" '')${R}   ${D}recompress-cycle to change${R}"
    printf '\n'
    printf '  %s%-6s %-9s %5s %7s %10s %9s %9s%s\n' "$D" "tier" "algo" "runs" "last" "interval" "idle age" "budget" "$R"
    local t c
    for t in 1 2 3; do
        c=$(ev_count recompress "tier$t")
        printf '  %-6s %-9s %5s %7s %10s %9s %9s\n' \
            "$t" \
            "$(conf_str "TIER${t}_ALGO" zstd):$(conf_str "TIER${t}_LEVEL" '')" \
            "$c" \
            "$(hhmm "$(ev_last recompress "tier$t")")" \
            "$(dur "$(conf_get "TIER${t}_INTERVAL" 0)")" \
            "$(dur "$(conf_get "TIER${t}_IDLE_AGE" 0)")" \
            "$(conf_get "TIER${t}_BUDGET_MIB" 0) MiB"
    done
    printf '\n'
    local saved
    saved=$(ev | awk '/action=recompress/ {
        b=0; e=0
        for(i=1;i<=NF;i++){ split($i,x,"="); if(x[1]=="before_used") b=x[2]; if(x[1]=="after_used") e=x[2] }
        d=b-e; if (d>0) s+=d
    } END{print s+0}')
    row "reclaimed" "$(hb "$saved")   ${D}this boot${R}"
    row "zram now" "$(hb "$MM_ORIG") → ${W}$(hb "$MM_USED")${R}   ${D}$(awk -v o="$MM_ORIG" -v u="$MM_USED" 'BEGIN{printf "%.2fx", (u?o/u:0)}')${R}"
    local d
    d=$(ev_count recompress)
    [ "$d" -eq 0 ] && note "no recompression passes this boot" || true
    printf '\n'
}

policy_show() {
    hdr "zram tier policy"
    note "$TIER_CONF"
    printf '\n'
    row "pipeline" "$(pipeline)"
    row "writeback" "$([ "$(conf_get WRITEBACK_ENABLED 1)" = 1 ] && printf '%senabled%s' "$GRN" "$R" || printf '%sdisabled%s' "$RED" "$R")"
    printf '\n'
    printf '  %s%-6s %-9s %10s %10s %9s%s\n' "$D" "tier" "algo" "interval" "idle age" "budget" "$R"
    local t
    for t in 1 2 3; do
        printf '  %-6s %-9s %10s %10s %9s\n' "$t" \
            "$(conf_str "TIER${t}_ALGO" zstd):$(conf_str "TIER${t}_LEVEL" '')" \
            "$(dur "$(conf_get "TIER${t}_INTERVAL" 0)")" \
            "$(dur "$(conf_get "TIER${t}_IDLE_AGE" 0)")" \
            "$(conf_get "TIER${t}_BUDGET_MIB" 0) MiB"
    done
    printf '\n'
    row "wb trigger" "zram ≥ ${W}$(conf_get WRITEBACK_HIGH_RATIO 85)%${R} full ${D}· or ≥ $(conf_get WRITEBACK_LOW_RATIO 70)% after $(dur "$(conf_get WRITEBACK_COOLDOWN 14400)")${R}"
    row "wb gates" "GPU ≤ $(conf_get WRITEBACK_MAX_GPU_BUSY 10)% busy ${D}·${R} IO stall < $(conf_get WRITEBACK_MAX_IO_STALL 2)%"
    row "wb budget" "$(hb $(( $(conf_get WRITEBACK_PASS_MIB 256) * 1048576 ))) per pass ${D}·${R} $(hb $(( $(conf_get WRITEBACK_BOOT_QUOTA_MIB 4096) * 1048576 ))) per boot"
    printf '\n'
    note "change a value:  memory-tools.sh policy set TIER1_INTERVAL 3600"
    printf '\n'
}

policy_set() {
    local key=${1:-} value=${2:-}
    [ -n "$key" ] && [ -n "$value" ] || { printf 'usage: memory-tools.sh policy set KEY VALUE\n' >&2; return 2; }
    case "$key" in
        TIER[123]_INTERVAL|TIER[123]_IDLE_AGE|TIER[123]_BUDGET_MIB|\
        WRITEBACK_ENABLED|WRITEBACK_HIGH_RATIO|WRITEBACK_LOW_RATIO|\
        WRITEBACK_COOLDOWN|WRITEBACK_MAX_GPU_BUSY|WRITEBACK_MAX_IO_STALL|\
        WRITEBACK_PASS_MIB|WRITEBACK_BOOT_QUOTA_MIB) ;;
        TIER[123]_ALGO|PRIMARY_ALGO)
            printf 'algorithms are set by zram-profile-stage, not here\n' >&2; return 2 ;;
        *) printf 'unknown key: %s\n' "$key" >&2; return 2 ;;
    esac
    case "$value" in ''|*[!0-9]*) printf 'value must be a non-negative integer\n' >&2; return 2 ;; esac
    grep -q "^$key=" "$TIER_CONF" || { printf '%s is not present in %s\n' "$key" "$TIER_CONF" >&2; return 2; }
    local old
    old=$(conf_get "$key" 0)
    sudo -n sed -i "s|^$key=.*|$key=$value|" "$TIER_CONF" || { printf 'could not write %s\n' "$TIER_CONF" >&2; return 1; }
    printf '  %s%s%s  %s → %s%s%s\n' "$W" "$key" "$R" "$old" "$GRN" "$value" "$R"
    note "active on the next tier-manager cycle"
}

gpu_short() {
    [ -r "$CARD/mem_info_vram_used" ] || { echo "Unavailable"; return; }
    awk -v u="$(cat "$CARD/mem_info_vram_used")" -v t="$(cat "$CARD/mem_info_vram_total")" \
        -v b="$(cat "$CARD/gpu_busy_percent")" 'BEGIN{printf "%.0f%% VRAM · %d%% GPU\n", (t?u*100/t:0), b}'
}

gpu_status() {
    [ "$RENDER" = oneline ] && { gpu_short; return; }
    [ -r "$CARD/mem_info_vram_used" ] || { hdr "AMDGPU"; note "unavailable"; printf '\n'; return; }
    local used total busy
    used=$(cat "$CARD/mem_info_vram_used"); total=$(cat "$CARD/mem_info_vram_total")
    busy=$(cat "$CARD/gpu_busy_percent")
    hdr "AMDGPU memory"
    row "VRAM" "$(bar "$used" "$total")   ${W}$(hb "$used")${R} ${D}of $(hb "$total")${R}"
    row "busy" "$busy%"
    row "level" "$(cat "$CARD/power_dpm_force_performance_level" 2>/dev/null || echo unknown)"
    row "PCIe" "$(cat "$CARD/current_link_speed" 2>/dev/null || echo '?') x$(cat "$CARD/current_link_width" 2>/dev/null || echo '?')"
    printf '\n'
}

gpu_report() {
    local body
    body="$(gpu_short)
Level: $(cat "$CARD/power_dpm_force_performance_level" 2>/dev/null || echo unknown)
VRAM: $(hb "$(cat "$CARD/mem_info_vram_used")") / $(hb "$(cat "$CARD/mem_info_vram_total")")"
    notify "AMDGPU memory" "$body"
    gpu_status
}

overview() {
    read_mm; read_bd
    local avail total swap_used written quota
    total=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)
    avail=$(awk '/^MemAvailable:/{print $2*1024}' /proc/meminfo)
    swap_used=$(awk '$1=="/dev/zram0"{print $4*1024}' /proc/swaps)
    : "${swap_used:=0}"
    written=$(boot_written_pages)
    quota=$(( $(conf_get WRITEBACK_BOOT_QUOTA_MIB 4096) * 1024 * 1024 / PAGE ))
    hdr "Memory"
    row "RAM in use" "$(bar $((total-avail)) "$total")   ${W}$(hb "$avail")${R} ${D}still available of $(hb "$total")${R}"
    row "zram swap" "$(hb "$swap_used") ${D}swapped →${R} ${W}$(hb "$MM_USED")${R} ${D}RAM · $(awk -v o="$MM_ORIG" -v u="$MM_USED" 'BEGIN{printf "%.2fx", (u?o/u:0)}')${R}"
    row "on NVMe" "$(hpg "$BD_COUNT")   ${D}$(hpg "$written") written this boot${R}"
    row "pipeline" "$(pipeline)"
    printf '\n'
    writeback_status
    recompress_status
}

usage() {
    cat <<'EOF'

  memory-tools.sh — zram tier, writeback and GPU memory control

  STATUS
    status                       memory, writeback and recompression overview
    writeback-status             NVMe writeback totals for this boot
    recompress-status            recompression passes for this boot
    gpu-status                   VRAM and GPU utilisation
    policy                       show the automatic tier policy

  RECOMPRESSION
    recompress-run               run the selected tier now
    recompress-cycle             select tier1 → tier2 → tier3 → tier1

  WRITEBACK TO NVMe             counts against a per-boot quota
    writeback-cold [SECONDS]     pages idle ≥ 24h (default)
    writeback-idle [SECONDS]     pages idle ≥ 30m (default)
    writeback-huge               incompressible huge pages
    writeback-huge-idle [SEC]    huge pages idle ≥ 3h (default)
    writeback-incompressible     pages that did not compress
    writeback-all                ignores the boot quota
    writeback-quota-reset        reset the accounting baseline only

  RECLAIM
    drop-caches                  clean page cache, dentries, inodes
    compact-memory               global physical compaction
    compact-zram                 zram allocator compaction
    gpu-evict                    evict AMDGPU VRAM to system memory

  POLICY
    policy                       show cadence, budgets and gates
    policy set KEY VALUE         change one value

  FLAGS
    --report                     force the full report
    --oneline                    force the single-line form
    --no-color                   disable colour

EOF
}

case "${1:-status}" in
    status)                   overview ;;
    writeback-status)         writeback_status ;;
    recompress-status)        recompress_status ;;
    gpu-status)               gpu_status ;;
    gpu-report)               gpu_report ;;
    policy)
        case "${2:-show}" in
            show) policy_show ;;
            set)  policy_set "${3:-}" "${4:-}" ;;
            *)    printf 'usage: memory-tools.sh policy [show|set KEY VALUE]\n' >&2; exit 2 ;;
        esac ;;
    recompress-cycle)
        cur=$(recompress_mode)
        case "$cur" in tier1) next=tier2 ;; tier2) next=tier3 ;; *) next=tier1 ;; esac
        mkdir -p "$MODE_DIR"; printf '%s\n' "$next" >"$MODE_FILE"
        notify "ZRAM recompression" "Selected $next"
        if [ "$RENDER" = oneline ]; then
            printf '%s\n' "$next"
        else
            hdr "ZRAM recompression"
            row "selected" "${W}$next${R}  ${D}$(conf_str "${next^^}_ALGO" zstd):$(conf_str "${next^^}_LEVEL" '')${R}"
            note "run it with: memory-tools.sh recompress-run"
            printf '\n'
        fi ;;
    recompress-run)           m=$(recompress_mode); run_root "ZRAM recompression" recompress "$m" recompress "$m" ;;
    writeback-quota-reset)    run_root "Writeback quota reset" plain '' writeback quota-reset ;;
    writeback-cold)           run_root "ZRAM writeback" writeback cold writeback cold ${2:+"$2"} ;;
    writeback-idle)           run_root "ZRAM writeback" writeback idle writeback idle ${2:+"$2"} ;;
    writeback-huge)           run_root "ZRAM writeback" writeback huge writeback huge ;;
    writeback-huge-idle)      run_root "ZRAM writeback" writeback huge-idle writeback huge-idle ${2:+"$2"} ;;
    writeback-incompressible) run_root "ZRAM writeback" writeback incompressible writeback incompressible ;;
    writeback-all)            run_root "ZRAM writeback" writeback all writeback all ;;
    drop-caches)              run_root "Drop caches" plain '' drop-caches ;;
    compact-memory)           run_root "Memory compaction" plain '' compact-memory ;;
    compact-zram)             run_root "ZRAM compaction" plain '' compact-zram ;;
    gpu-evict)                run_root "AMDGPU VRAM eviction" plain '' gpu-evict ;;
    help|--help|-h)           usage ;;
    *)                        usage >&2; exit 2 ;;
esac
