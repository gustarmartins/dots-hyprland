#!/usr/bin/env sh
DO_STATE=$(hyprctl getoption render:direct_scanout | awk 'NR==1{print $2}')

if [ "$DO_STATE" = 0 ] ; then
    # --- ENABLE TEARING ---
    hyprctl keyword render:direct_scanout 1
    hyprctl notify 1 5000 "rgb(40a02b)" "Direct Scanout [ENABLED]"
else
    # --- DISABLE TEARING ---
    hyprctl keyword render:direct_scanout 0
    hyprctl notify 1 5000 "rgb(d20f39)" "Direct Scanout [DISABLED]"
fi
