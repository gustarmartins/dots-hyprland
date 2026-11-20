#!/usr/bin/env bash
# On-demand AMD clock controls. No voltage, power-limit or fan-curve changes.
set -euo pipefail

mode=${1:-toggle}
if [[ ${0##*/} == gpu-mode && $# == 0 ]]; then mode=status; fi
case "$mode" in
    status|auto|high|max|toggle) ;;
    *) printf 'Usage: gpu-mode {status|auto|high|max|toggle}\n' >&2; exit 2 ;;
esac

shopt -s nullglob
devices=()
for candidate in /sys/class/drm/card[0-9]*/device; do
    [[ -r "$candidate/vendor" && -f "$candidate/power_dpm_force_performance_level" ]] || continue
    [[ $(<"$candidate/vendor") == 0x1002 ]] && devices+=("$candidate")
done
if (( ${#devices[@]} != 1 )); then
    printf 'Expected one controllable AMD GPU; found %d. No changes made.\n' "${#devices[@]}" >&2
    exit 1
fi
device=${devices[0]}
dpm=$device/power_dpm_force_performance_level

status() {
    printf 'AMD GPU %s | mode: %s\n' "$(basename "$(readlink -f "$device")")" "$(<"$dpm")"
    for clock in sclk mclk; do
        printf '%s: ' "$clock"
        awk '/\*/ {print}' "$device/pp_dpm_$clock"
    done
    for hwmon in "$device"/hwmon/hwmon*; do
        if [[ -r "$hwmon/power1_cap" && -r "$hwmon/power1_cap_default" ]]; then
            printf 'Power limit: %s W (default %s W)\n' \
                "$(( $(<"$hwmon/power1_cap") / 1000000 ))" \
                "$(( $(<"$hwmon/power1_cap_default") / 1000000 ))"
        fi
    done
}

if [[ $mode == status ]]; then status; exit; fi
exec 9>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gpu-mode.lock"
flock -n 9 || { printf 'Another GPU mode change is running.\n' >&2; exit 1; }
[[ -w $dpm ]] || { printf 'GPU clock control is not writable by this user.\n' >&2; exit 1; }
notify=false
if [[ $mode == toggle ]]; then
    notify=true
    if [[ $(<"$dpm") == auto ]]; then mode=max; else mode=auto; fi
fi

if [[ $mode == max ]]; then
    # Request the highest existing clock states without overclocking.
    # Re-arm through auto so a previous manual mask is not retained.
    for clock in sclk mclk; do
        [[ -w "$device/pp_dpm_$clock" ]] || { printf 'Clock mask is not writable: %s\n' "$clock" >&2; exit 1; }
    done
    top_sclk=$(awk -F: '/^[[:space:]]*[0-9]+:/ {if ($1+0 > top) top=$1+0; found=1} END {if (found) print top+0}' "$device/pp_dpm_sclk")
    top_mclk=$(awk -F: '/^[[:space:]]*[0-9]+:/ {if ($1+0 > top) top=$1+0; found=1} END {if (found) print top+0}' "$device/pp_dpm_mclk")
    [[ $top_sclk =~ ^[0-9]+$ && $top_mclk =~ ^[0-9]+$ ]] || exit 1
    trap 'printf "auto\n" > "$dpm"; printf "Clock request failed; restored auto.\n" >&2' ERR
    printf 'auto\n' > "$dpm"
    printf 'manual\n' > "$dpm"
    printf '%s\n' "$top_sclk" > "$device/pp_dpm_sclk"
    printf '%s\n' "$top_mclk" > "$device/pp_dpm_mclk"
    [[ $(<"$dpm") == manual ]]
    trap - ERR
    message='Highest available GPU clock states requested; power and thermal limits still apply.'
else
    printf '%s\n' "$mode" > "$dpm"
    [[ $(<"$dpm") == "$mode" ]]
    message="GPU clock mode: $mode"
fi
status
if $notify && command -v notify-send >/dev/null; then
    notify-send -a 'GPU controls' -i video-display 'GPU clock mode' "$message" || true
fi
