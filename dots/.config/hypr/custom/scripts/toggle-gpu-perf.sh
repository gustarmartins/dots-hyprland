#!/usr/bin/env bash
# Toggles AMD GPU performance level between 'auto' (dynamic) and 'high' (forced max)

DPM_FILE=$(ls /sys/class/drm/card*/device/power_dpm_force_performance_level | head -n 1)

if [ -z "$DPM_FILE" ]; then
    notify-send "GPU Error" "Could not find AMD GPU DPM control file."
    exit 1
fi

CURRENT_STATE=$(cat "$DPM_FILE")

if [ "$CURRENT_STATE" = "auto" ]; then
    # Switch to HIGH (max always)
    pkexec bash -c "echo high > $DPM_FILE"
    
    # Verify
    NEW_STATE=$(cat "$DPM_FILE")
    if [ "$NEW_STATE" = "high" ]; then
        notify-send -u critical -i video-display "GPU Performance Menu" "AMD GPU forced to MAX PERFORMANCE (High)"
    else
        notify-send -u normal "GPU Error" "Failed to set high performance mode."
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
