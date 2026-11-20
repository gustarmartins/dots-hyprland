#!/usr/bin/env bash
# Keep Quickshell alive. QS 0.2.1's PipeWire binding can segfault when the
# PipeWire core connection is torn down (e.g. `systemctl --user restart
# pipewire`). QS's crash handler only writes a report; it does not relaunch.
# This loop respawns it, with a backoff guard so a crash-on-startup bug can't
# turn into a busy spin.
qsConfig="${1:-ii}"

min_uptime=5      # seconds; runs shorter than this count as a "fast crash"
fast_crashes=0

# The supervisor can outlive Hyprland after a crash. Its inherited instance
# signature then points at a dead IPC socket, even if Wayland reuses its name.
# Resolve the compositor for this display before EVERY launch. Do not select
# another desktop/nested compositor just because it happens to be the newest.
refresh_hyprland_environment() {
    local instances selected signature display
    instances=$(timeout 3 hyprctl instances -j 2>/dev/null) || return 1
    selected=$(jq -er --arg signature "${HYPRLAND_INSTANCE_SIGNATURE:-}" \
        --arg display "${WAYLAND_DISPLAY##*/}" '
        [.[] | select((.instance | type) == "string" and .instance != ""
            and (.wl_socket | type) == "string" and .wl_socket != "")] as $all
        | [$all[] | select(.instance == $signature
            and ($display == "" or .wl_socket == $display))] as $inherited
        | (if ($inherited | length) == 1 then $inherited
           else [$all[] | select(.wl_socket == $display)] end) as $matches
        | select(($matches | length) == 1)
        | $matches[0] | [.instance, .wl_socket] | @tsv
    ' <<< "$instances" 2>/dev/null) || return 1
    IFS=$'\t' read -r signature display <<< "$selected"
    [[ -n "$signature" && -n "$display" ]] || return 1
    if [[ "$signature" != "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        printf 'Quickshell: reconnecting to Hyprland instance %s on %s\n' "$signature" "$display" >&2
    fi
    export HYPRLAND_INSTANCE_SIGNATURE="$signature" WAYLAND_DISPLAY="$display"
}

# Hyprland/systemd start without ~/.local/bin in PATH; prefer user wrapper over
# /usr/bin/qs (e.g. noswap launcher) while honoring explicit PATH overrides.
resolve_qs_bin() {
    local current
    current="$(command -v qs || true)"
    if [[ ( -z "$current" || "$current" == /usr/bin/* ) && -x "$HOME/.local/bin/qs" ]]; then
        printf '%s\n' "$HOME/.local/bin/qs"
    else
        printf '%s\n' "${current:-qs}"
    fi
}

while true; do
    # A watchdog restart can leave a short gap with no compositor. Bound the
    # wait, and stop after logout instead of launching against a stale socket.
    ready=false
    for ((attempt = 0; attempt < 15; attempt++)); do
        if refresh_hyprland_environment; then
            ready=true
            break
        fi
        sleep 1
    done
    if [[ "$ready" != true ]]; then
        printf 'Quickshell: no Hyprland instance for display %s; stopping.\n' "${WAYLAND_DISPLAY:-unset}" >&2
        exit 1
    fi

    # A process launched while the bus is down caches an unusable Qt connection.
    # Pin the live generation before starting; QML detects a later replacement.
    bus_helper="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/$qsConfig/scripts/session_bus.py"
    if [[ -f "$bus_helper" ]]; then
        QS_SESSION_BUS_ID=$(/usr/bin/python3 "$bus_helper" --ready --timeout 15)
        if [[ $? -ne 0 || -z "$QS_SESSION_BUS_ID" ]]; then
            printf 'Quickshell: session bus unavailable; waiting before launch.\n' >&2
            sleep 5
            continue
        fi
        export QS_SESSION_BUS_ID
    fi

    start=$(date +%s)
    # Load config / login can also start a supervisor while one survived.
    qsBin="$(resolve_qs_bin)"
    "$qsBin" --no-duplicate -c "$qsConfig"
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
