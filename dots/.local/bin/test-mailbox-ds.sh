#!/usr/bin/env bash
# ============================================================================
# TEST 1: Mailbox + Triple Buffer + Direct Scanout
# ============================================================================
# new_render_scheduling = true  (triple buffer / mailbox)
# direct_scanout        = 1     (bypass compositor for fullscreen)
# ============================================================================
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
# Change this if osu!lazer is installed differently (e.g. flatpak, AppImage)
OSU_CMD="${OSU_CMD:-osu.AppImage}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"   # seconds between monitor polls
# ────────────────────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  TEST 1: Mailbox + Triple Buffer + Direct Scanout           ║"
echo "║                                                              ║"
echo "║  render:new_render_scheduling = true                         ║"
echo "║  render:direct_scanout        = 1                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Save current values ────────────────────────────────────────────────────
echo "[*] Saving current Hyprland settings..."
ORIG_NRS=$(hyprctl getoption render:new_render_scheduling -j | grep -oP '"int":\s*\K\d+' || echo "0")
ORIG_DS=$(hyprctl getoption render:direct_scanout -j | grep -oP '"int":\s*\K\d+' || echo "0")

# For bool options, getoption returns int 0/1
# new_render_scheduling is bool -> stored as int 0 or 1
echo "    render:new_render_scheduling was: $ORIG_NRS"
echo "    render:direct_scanout        was: $ORIG_DS"

# ── Apply test settings ────────────────────────────────────────────────────
echo ""
echo "[*] Applying test settings..."
hyprctl --batch "keyword render:new_render_scheduling true ; keyword render:direct_scanout 1"
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
WATCHER_LOG=$(mktemp /tmp/test1-monitor-XXXXXX.log)

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
    # Convert int back to bool string for new_render_scheduling
    local nrs_val="false"
    [[ "$ORIG_NRS" == "1" ]] && nrs_val="true"
    hyprctl --batch "keyword render:new_render_scheduling $nrs_val ; keyword render:direct_scanout $ORIG_DS"
    echo "[✓] Settings restored."

    # ── Post-game monitor report ────────────────────────────────────────────
    _parse_monitor_fields
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  DIRECT SCANOUT MONITOR REPORT                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Purpose: Did Direct Scanout engage while the game was running?"
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

    # Check if DS ever engaged during the session
    local ds_engaged=false
    if [[ -f "$WATCHER_LOG" ]]; then
        while IFS='|' read -r _ts _sol _solb _tear _tearb ds_val _dsb; do
            if [[ "$ds_val" != "0" && -n "$ds_val" ]]; then
                ds_engaged=true
                break
            fi
        done < "$WATCHER_LOG"
    fi

    if $ds_engaged; then
        echo "  ✅ Direct Scanout DID engage at some point during the session!"
    else
        echo "  ❌ Direct Scanout NEVER engaged during the session."
        if [[ -n "$DS_BLOCKED" && "$DS_BLOCKED" != "none" ]]; then
            echo "     Blocked by: $DS_BLOCKED"
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
echo "[*] Launching osu!lazer (Wayland + SDL3)..."
echo "    Close the game to end the test and restore settings."
echo "    📡 Monitoring hyprctl monitors all every ${POLL_INTERVAL}s in background..."
echo ""

env OSU_SDL3=1 SDL_VIDEO_DRIVER=wayland "$OSU_CMD" || true

echo ""
echo "[✓] Test 1 complete."
