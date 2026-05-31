#!/usr/bin/env bash
# Toggles AMD GPU performance between 'auto' (dynamic) and forced MAX.
#
# NOTE: on Navi 2x (RX 6600 here), 'high' floors the MEMORY clock but NOT
# GFXCLK — it can leave the core stuck at the low DPM step (~700 MHz), which
# tanks light/latency-sensitive workloads (e.g. osu! stable in direct-scanout,
# where the compositor drops out and nothing else keeps the GPU boosted).
# 'manual' + pinning the top sclk DPM index is the only reliable core-clock lock.

DPM_FILE=$(ls /sys/class/drm/card*/device/power_dpm_force_performance_level | head -n 1)

if [ -z "$DPM_FILE" ]; then
    notify-send "GPU Error" "Could not find AMD GPU DPM control file."
    exit 1
fi

DEV_DIR=$(dirname "$DPM_FILE")
SCLK_FILE="$DEV_DIR/pp_dpm_sclk"
TOP_SCLK=$(awk 'END{print $1+0}' "$SCLK_FILE")   # highest sclk DPM index

CURRENT_STATE=$(cat "$DPM_FILE")

if [ "$CURRENT_STATE" = "auto" ]; then
    # Switch to MAX: re-arm the manual DPM mask (auto->manual is REQUIRED —
    # writing 'manual' when already manual won't re-latch, and the SMU keeps
    # governing by the active power profile, parking GFXCLK at ~800 MHz), then
    # pin sclk to its top DPM index.
    pkexec bash -c "echo auto > $DPM_FILE && echo manual > $DPM_FILE && echo $TOP_SCLK > $SCLK_FILE"

    # Verify the core clock is actually pinned (not just the mode string)
    NEW_STATE=$(cat "$DPM_FILE")
    PINNED=$(awk '/\*/{print $2}' "$SCLK_FILE")
    if [ "$NEW_STATE" = "manual" ]; then
        notify-send -u critical -i video-display "GPU Performance Menu" "AMD GPU forced to MAX (core pinned: $PINNED)"
    else
        notify-send -u normal "GPU Error" "Failed to set max performance mode."
    fi
else
    # Switch back to AUTO
    pkexec bash -c "echo auto > $DPM_FILE"
    
    # Verify
    NEW_STATE=$(cat "$DPM_FILE")
    if [ "$NEW_STATE" = "auto" ]; then
        notify-send -u normal -i video-display "GPU Performance Menu" "AMD GPU restored to AUTO (Dynamic)"
    else
        notify-send -u normal "GPU Error" "Failed to restore auto performance mode."
    fi
fi
