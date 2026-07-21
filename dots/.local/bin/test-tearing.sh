#!/usr/bin/env bash
# ============================================================================
# TEST 2: Full Tearing (Immediate Mode)
# ============================================================================
# general:allow_tearing       = true  (master tearing toggle)
# cursor:no_hardware_cursors  = 1     (force software cursors — hw cursor
#                                       blocks tearing on Vega 11!)
# SDL_VIDEO_DOUBLE_BUFFER     = 1     (required for tearing under SDL/Wayland)
#
# NOTE: osu! must already have an `immediate` window rule in the Lua config.
# ============================================================================
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
OSU_CMD="${OSU_CMD:-osu.AppImage}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"   # seconds between monitor polls
# ────────────────────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  TEST 2: Full Tearing (Immediate Mode)                      ║"
echo "║                                                              ║"
echo "║  general:allow_tearing       = true                          ║"
echo "║  cursor:no_hardware_cursors  = 1  (fixes Vega 11 blocker)   ║"
echo "║  + SDL_VIDEO_DOUBLE_BUFFER=1                                 ║"
echo "║                                                              ║"
echo "║  Make sure you have:                                         ║"
echo "║    immediate = true for the osu! window class                ║"
echo "║  in your Hyprland Lua window rules                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Save current values ────────────────────────────────────────────────────
echo "[*] Saving current Hyprland settings..."
ORIG_TEARING=$(hyprctl getoption general:allow_tearing -j | grep -oP '"int":\s*\K\d+' || echo "0")
ORIG_HWCURSOR=$(hyprctl getoption cursor:no_hardware_cursors -j | grep -oP '"int":\s*\K\d+' || echo "2")

echo "    general:allow_tearing       was: $ORIG_TEARING"
echo "    cursor:no_hardware_cursors  was: $ORIG_HWCURSOR"

# ── Apply test settings ────────────────────────────────────────────────────
echo ""
echo "[*] Applying test settings..."
hyprctl eval 'hl.config({ general = { allow_tearing = true }, cursor = { no_hardware_cursors = 1 } })'
echo "[✓] Settings applied."
echo ""
echo "[!] NOTE: hw cursors have been disabled to unblock tearing on Vega 11."
echo "    (tearingBlockedBy included 'hw cursor' in your hyprctl monitors output)"

# ── Capture baseline monitor state ─────────────────────────────────────────
_parse_monitor_fields() {
    local output
    output=$(hyprctl monitors all 2>/dev/null)
    SOLITARY=$(echo "$output"           | grep -oP '^\s*solitary:\s*\K.*' | head -1)
    SOLITARY_BLOCKED=$(echo "$output"   | grep -oP '^\s*solitaryBlockedBy:\s*\K.*' | head -1)
    ACTIVELY_TEARING=$(echo "$output"   | grep -oP '^\s*activelyTearing:\s*\K.*' | head -1)
    TEARING_BLOCKED=$(echo "$output"    | grep -oP '^\s*tearingBlockedBy:\s*\K.*' | head -1)
    DS_TO=$(echo "$output"              | grep -oP '^\s*directScanoutTo:\s*\K.*' | head -1)
    DS_BLOCKED=$(echo "$output"         | grep -oP '^\s*directScanoutBlockedBy:\s*\K.*' | head -1)
}

_parse_monitor_fields
BASELINE_SOLITARY="$SOLITARY"
BASELINE_SOLITARY_BLOCKED="$SOLITARY_BLOCKED"
BASELINE_ACTIVELY_TEARING="$ACTIVELY_TEARING"
BASELINE_TEARING_BLOCKED="$TEARING_BLOCKED"
BASELINE_DS_TO="$DS_TO"
BASELINE_DS_BLOCKED="$DS_BLOCKED"

echo ""
echo "[*] Baseline monitor state (before game):"
echo "        solitary:                 $BASELINE_SOLITARY"
echo "        solitaryBlockedBy:        $BASELINE_SOLITARY_BLOCKED"
echo "        activelyTearing:          $BASELINE_ACTIVELY_TEARING"
echo "        tearingBlockedBy:         $BASELINE_TEARING_BLOCKED"
echo "        directScanoutTo:          $BASELINE_DS_TO"
echo "        directScanoutBlockedBy:   $BASELINE_DS_BLOCKED"

# ── Background monitor watcher ─────────────────────────────────────────────
WATCHER_LOG=$(mktemp /tmp/test2-monitor-XXXXXX.log)

(
    while true; do
        _parse_monitor_fields_bg() {
            local output
            output=$(hyprctl monitors all 2>/dev/null)
            echo "$output" | grep -oP '^\s*solitary:\s*\K.*' | head -1
            echo "$output" | grep -oP '^\s*solitaryBlockedBy:\s*\K.*' | head -1
            echo "$output" | grep -oP '^\s*activelyTearing:\s*\K.*' | head -1
            echo "$output" | grep -oP '^\s*tearingBlockedBy:\s*\K.*' | head -1
            echo "$output" | grep -oP '^\s*directScanoutTo:\s*\K.*' | head -1
            echo "$output" | grep -oP '^\s*directScanoutBlockedBy:\s*\K.*' | head -1
        }
        readarray -t fields < <(_parse_monitor_fields_bg)
        ts=$(date '+%H:%M:%S')
        echo "$ts|${fields[0]:-?}|${fields[1]:-?}|${fields[2]:-?}|${fields[3]:-?}|${fields[4]:-?}|${fields[5]:-?}" >> "$WATCHER_LOG"
        sleep "$POLL_INTERVAL"
    done
) &
WATCHER_PID=$!

# ── Cleanup trap ────────────────────────────────────────────────────────────
restore_settings() {
    # Kill the background watcher
    kill "$WATCHER_PID" 2>/dev/null; wait "$WATCHER_PID" 2>/dev/null || true

    echo ""
    echo "[*] Restoring original Hyprland settings..."
    local tear_val="false"
    [[ "$ORIG_TEARING" == "1" ]] && tear_val="true"
    hyprctl eval "hl.config({ general = { allow_tearing = $tear_val }, cursor = { no_hardware_cursors = $ORIG_HWCURSOR } })"
    echo "[✓] Settings restored."

    # ── Post-game monitor report ────────────────────────────────────────────
    _parse_monitor_fields
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  TEARING MONITOR REPORT                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Purpose: Did Tearing engage while the game was running?"
    echo ""
    echo "  ┌─────────────────────────────┬─────────────────────────────────────────┬─────────────────────────────────────────┐"
    echo "  │ Field                       │ Before (baseline)                       │ After (game exit)                       │"
    echo "  ├─────────────────────────────┼─────────────────────────────────────────┼─────────────────────────────────────────┤"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "solitary"              "$BASELINE_SOLITARY"           "$SOLITARY"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "solitaryBlockedBy"     "$BASELINE_SOLITARY_BLOCKED"   "$SOLITARY_BLOCKED"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "activelyTearing"       "$BASELINE_ACTIVELY_TEARING"   "$ACTIVELY_TEARING"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "tearingBlockedBy"      "$BASELINE_TEARING_BLOCKED"    "$TEARING_BLOCKED"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "directScanoutTo"       "$BASELINE_DS_TO"              "$DS_TO"
    printf "  │ %-27s │ %-39s │ %-39s │\n" "directScanoutBlockedBy" "$BASELINE_DS_BLOCKED"        "$DS_BLOCKED"
    echo "  └─────────────────────────────┴─────────────────────────────────────────┴─────────────────────────────────────────┘"
    echo ""

    # Check if tearing ever engaged during the session
    local tearing_engaged=false
    local tearing_count=0
    local total_samples=0
    if [[ -f "$WATCHER_LOG" ]]; then
        while IFS='|' read -r _ts _sol _solb tear_val _tearb _ds _dsb; do
            ((total_samples++)) || true
            if [[ "$tear_val" == "true" ]]; then
                tearing_engaged=true
                ((tearing_count++)) || true
            fi
        done < "$WATCHER_LOG"
    fi

    if $tearing_engaged; then
        echo "  ✅ Tearing DID engage during the session!"
        echo "     Observed tearing in $tearing_count / $total_samples samples."
    else
        echo "  ❌ Tearing NEVER engaged during the session."
        if [[ -n "$TEARING_BLOCKED" && "$TEARING_BLOCKED" != "none" ]]; then
            echo "     Blocked by: $TEARING_BLOCKED"
        fi
    fi

    # Show if anything changed
    echo ""
    local any_change=false
    [[ "$BASELINE_SOLITARY" != "$SOLITARY" ]] && echo "  ⚡ solitary changed: $BASELINE_SOLITARY → $SOLITARY" && any_change=true
    [[ "$BASELINE_SOLITARY_BLOCKED" != "$SOLITARY_BLOCKED" ]] && echo "  ⚡ solitaryBlockedBy changed: $BASELINE_SOLITARY_BLOCKED → $SOLITARY_BLOCKED" && any_change=true
    [[ "$BASELINE_ACTIVELY_TEARING" != "$ACTIVELY_TEARING" ]] && echo "  ⚡ activelyTearing changed: $BASELINE_ACTIVELY_TEARING → $ACTIVELY_TEARING" && any_change=true
    [[ "$BASELINE_TEARING_BLOCKED" != "$TEARING_BLOCKED" ]] && echo "  ⚡ tearingBlockedBy changed: $BASELINE_TEARING_BLOCKED → $TEARING_BLOCKED" && any_change=true
    [[ "$BASELINE_DS_TO" != "$DS_TO" ]] && echo "  ⚡ directScanoutTo changed: $BASELINE_DS_TO → $DS_TO" && any_change=true
    [[ "$BASELINE_DS_BLOCKED" != "$DS_BLOCKED" ]] && echo "  ⚡ directScanoutBlockedBy changed: $BASELINE_DS_BLOCKED → $DS_BLOCKED" && any_change=true
    $any_change || echo "  (no fields changed between baseline and game exit)"

    echo ""
    # Cleanup temp log
    rm -f "$WATCHER_LOG"
}
trap restore_settings EXIT

# ── Launch osu!lazer ────────────────────────────────────────────────────────
echo ""
echo "[*] Launching osu!lazer (Wayland + SDL3 + Double Buffer for tearing)..."
echo "    Close the game to end the test and restore settings."
echo "    📡 Monitoring hyprctl monitors all every ${POLL_INTERVAL}s in background..."
echo ""

env OSU_SDL3=1 SDL_VIDEO_DRIVER=wayland SDL_VIDEO_DOUBLE_BUFFER=1 "$OSU_CMD" || true

echo ""
echo "[✓] Test 2 complete."
