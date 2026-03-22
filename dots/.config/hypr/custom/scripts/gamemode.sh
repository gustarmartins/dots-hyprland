#!/usr/bin/env sh
TEARING_STATE=$(hyprctl getoption general:allow_tearing | awk 'NR==1{print $2}')

if [ "$TEARING_STATE" = 0 ] ; then
    # --- ENABLE TEARING ---
    hyprctl keyword general:allow_tearing true
    hyprctl notify 1 5000 "rgb(40a02b)" "Tearing [ENABLED]"
else
    # --- DISABLE TEARING ---
    hyprctl keyword general:allow_tearing false
    hyprctl notify 1 5000 "rgb(d20f39)" "Tearing [DISABLED]"
fi
