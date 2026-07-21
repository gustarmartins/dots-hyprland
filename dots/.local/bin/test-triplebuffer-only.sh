#!/usr/bin/env bash
# ============================================================================
# TEST 3: Triple Buffer Only (No Direct Scanout)
# ============================================================================
# new_render_scheduling = true   (triple buffer / mailbox)
# direct_scanout        = 0     (OFF — compositor stays in the path)
#
# This isolates whether Direct Scanout is helping or hurting.
# If this test feels identical to Test 1, DS is not a factor.
# If Test 1 is better, DS is reducing latency.
# If this test is better, DS might be causing issues on the GPU/driver.
# ============================================================================
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
OSU_CMD="${OSU_CMD:-osu.AppImage}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"   # seconds between monitor polls
# ────────────────────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  TEST 3: Triple Buffer Only (NO Direct Scanout)             ║"
echo "║                                                              ║"
echo "║  render:new_render_scheduling = true                         ║"
echo "║  render:direct_scanout        = 0                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Save current values ────────────────────────────────────────────────────
echo "[*] Saving current Hyprland settings..."
ORIG_NRS=$(hyprctl getoption render:new_render_scheduling -j | grep -oP '"int":\s*\K\d+' || echo "0")
ORIG_DS=$(hyprctl getoption render:direct_scanout -j | grep -oP '"int":\s*\K\d+' || echo "0")

echo "    render:new_render_scheduling was: $ORIG_NRS"
echo "    render:direct_scanout        was: $ORIG_DS"

# ── Apply test settings ────────────────────────────────────────────────────
echo ""
echo "[*] Applying test settings..."
hyprctl --batch "keyword render:new_render_scheduling true ; keyword render:direct_scanout 0"
echo "[✓] Settings applied."

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
WATCHER_LOG=$(mktemp /tmp/test3-monitor-XXXXXX.log)

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
    local nrs_val="false"
    [[ "$ORIG_NRS" == "1" ]] && nrs_val="true"
    hyprctl --batch "keyword render:new_render_scheduling $nrs_val ; keyword render:direct_scanout $ORIG_DS"
    echo "[✓] Settings restored."

    # ── Post-game monitor report ────────────────────────────────────────────
    _parse_monitor_fields
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  TRIPLE BUFFER (NO DS) MONITOR REPORT                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Purpose: Confirm Direct Scanout stayed OFF (compositor-only path)."
    echo "  Compare this result with Test 1 to see if DS helps or hurts."
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

    # Verify DS stayed off
    local ds_leaked=false
    local total_samples=0
    if [[ -f "$WATCHER_LOG" ]]; then
        while IFS='|' read -r _ts _sol _solb _tear _tearb ds_val _dsb; do
            ((total_samples++)) || true
            if [[ "$ds_val" != "0" && -n "$ds_val" && "$ds_val" != "?" ]]; then
                ds_leaked=true
            fi
        done < "$WATCHER_LOG"
    fi

    if $ds_leaked; then
        echo "  ⚠️  Direct Scanout unexpectedly engaged even though it was set to 0!"
        echo "     This shouldn't happen — investigate your window rules."
    else
        echo "  ✅ Direct Scanout stayed OFF for all $total_samples samples (as expected)."
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
echo "[*] Launching osu!lazer (Wayland + SDL3)..."
echo "    Close the game to end the test and restore settings."
echo "    📡 Monitoring hyprctl monitors all every ${POLL_INTERVAL}s in background..."
echo ""

env OSU_SDL3=1 SDL_VIDEO_DRIVER=wayland "$OSU_CMD" || true

echo ""
echo "[✓] Test 3 complete."
