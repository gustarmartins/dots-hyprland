#!/usr/bin/env bash
# One response per input line. Closing the owning shell's pipe ends the reader.
# Sysfs reads run outside the QML thread. Missing or offline sensors report zero.
shopt -s nullglob
read_sensor() {
    REPLY=0
    if [[ -r $1 ]]; then
        { IFS= read -r REPLY < "$1"; } 2>/dev/null || :
        [[ $REPLY =~ ^-?[0-9]+$ ]] || REPLY=0
    fi
}

select_gpu() {
    local card candidate vendor first=
    device=
    for card in /sys/class/drm/card[0-9]*; do
        [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
        candidate=$card/device
        [[ -r $candidate/vendor ]] || continue
        IFS= read -r vendor < "$candidate/vendor" || continue
        [[ $vendor == 0x1002 ]] || continue
        if [[ -z $first ]]; then first=$candidate; fi
        read_sensor "$candidate/boot_vga"
        if [[ $REPLY == 1 ]]; then device=$candidate; return; fi
    done
    device=$first
}

case ${1:-} in
    gpu)
        select_gpu
        while IFS= read -r tick; do
            if [[ ! -d $device ]]; then
                select_gpu
                if [[ -z $device ]]; then
                    printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0\n'
                    continue
                fi
            fi
            hwmons=("$device"/hwmon/hwmon*)
            hwmon=${hwmons[0]:-"$device/hwmon/unavailable"}
            values=()
            for node in "$device"/{mem_info_vram_total,mem_info_vram_used,mem_info_gtt_total,mem_info_gtt_used,gpu_busy_percent,mem_busy_percent} \
                        "$hwmon"/{power1_average,power1_cap,temp1_input,temp2_input,temp3_input,freq1_input,freq2_input,fan1_input}; do
                read_sensor "$node"
                values+=("$REPLY")
            done
            printf '%s\n' "${values[*]}"
        done
        ;;
    cpu-clock)
        while IFS= read -r tick; do
            peak=0
            for node in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
                read_sensor "$node"
                (( REPLY > peak )) && peak=$REPLY
            done
            printf '%d\n' "$peak"
        done
        ;;
    *) exit 2 ;;
esac
exit 0
