#!/bin/bash
# Fix display quality after sleep/suspend/DPMS-off by re-applying
# monitor config so the DP link re-negotiates 10-bit (XRGB2101010).
#
# The root cause: amdgpu doesn't always restore the negotiated bit
# depth after a DPMS off→on cycle or S3 resume.  A bare `dpms on`
# brings the display back at 8-bit (XRGB8888).  Re-issuing the
# `monitor` keyword forces Hyprland to reset the DRM connector's
# max_bpc property and re-create the output, restoring 10-bit.

sleep 2

# Resolve Hyprland socket — works for both root (systemd service)
# and user (hypridle) contexts.
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /tmp/hypr/ 2>/dev/null | head -n1)
SOCK="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"

if [ ! -S "$SOCK" ]; then
    echo "fix-display-resume: Hyprland socket not found, aborting" >&2
    exit 1
fi

# Re-apply every monitor line from monitors.conf.  This is
# idempotent — Hyprland only modesets if something changed.
CONF_FILE="/home/gus/.config/hypr/monitors.conf"
while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    val="${line#monitor = }"
    [ "$val" = "$line" ] && val="${line#monitor=}"
    [ "$val" = "$line" ] && continue
    echo "fix-display-resume: re-applying monitor $val"
    hyprctl keyword monitor "$val"
done < "$CONF_FILE"
