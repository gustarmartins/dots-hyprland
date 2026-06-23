#!/usr/bin/env bash
# monitor-wake-fix.sh
# Aggressive fix for blurry AOC 27G2G4 (DP-1).
# 
# Uses 'monitor disable' to force the driver to kill the link entirely,
# which is more effective than DPMS for resetting the monitor's internal scaler.

MONITOR="DP-1"
MONITOR_CONF="1920x1080@144,0x0,1"
LOG_TAG="monitor-wake-fix"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | systemd-cat -t "$LOG_TAG" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Aggressive monitor wake fix triggered for $MONITOR"

# Step 1: Disable the monitor entirely (kills the signal/link)
hyprctl keyword monitor "$MONITOR,disable"
log "Monitor $MONITOR disabled (signal dropped)"

# Wait for driver/monitor to realize the link is gone
sleep 3

# Step 2: Re-enable with full config
hyprctl keyword monitor "$MONITOR,$MONITOR_CONF"
log "Monitor $MONITOR re-enabled with config: $MONITOR_CONF"

# Step 3: Give the AOC scaler time to wake up and lock
sleep 4

# Step 4: Final config re-apply to fix any missed handshake parameters (like 10-bit)
hyprctl keyword monitor "$MONITOR,$MONITOR_CONF"
log "Final config re-apply sent"

# Verification
current_format=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$MONITOR\") | .currentFormat" 2>/dev/null)
log "Fix complete — Current format: $current_format"
