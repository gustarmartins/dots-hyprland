#!/usr/bin/env bash
# Keep Quickshell alive. QS 0.2.1's PipeWire binding can segfault when the
# PipeWire core connection is torn down (e.g. `systemctl --user restart
# pipewire`). QS's crash handler only writes a report; it does not relaunch.
# This loop respawns it, with a backoff guard so a crash-on-startup bug can't
# turn into a busy spin.
qsConfig="${1:-ii}"

min_uptime=5      # seconds; runs shorter than this count as a "fast crash"
fast_crashes=0

while true; do
    start=$(date +%s)
    qs -c "$qsConfig"
    code=$?
    end=$(date +%s)

    # Clean exit (e.g. user asked QS to quit / reload) -> stop respawning.
    if [ "$code" -eq 0 ]; then
        break
    fi

    if [ $((end - start)) -lt "$min_uptime" ]; then
        fast_crashes=$((fast_crashes + 1))
    else
        fast_crashes=0
    fi

    # Too many crashes in a row: back off so we don't hammer the CPU.
    if [ "$fast_crashes" -ge 5 ]; then
        notify-send -u critical "Quickshell" "Crashed 5× rapidly (exit $code). Backing off 30s." 2>/dev/null
        sleep 30
        fast_crashes=0
    else
        sleep 1
    fi
done
