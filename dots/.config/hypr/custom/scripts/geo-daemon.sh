#!/usr/bin/env bash
#
# Float & Geometry IPC Daemon
#
# This is the IPC engine that powers two independent features:
#   1. Geometry Restore — restore saved window geometry (opt-in, Super+F10)
#   2. Master Float     — float all new windows at default size (Super+F11)
#
# The daemon itself is NOT user-facing. It auto-starts when either feature
# is enabled and auto-stops when both are off.
#
# Feature state files:
#   ~/.config/hypr/custom/.geo_restore_enabled  (exists = geometry ON)
#   /tmp/hypr_master_float_state                (exists = master float ON)
#
# Called with: geo-daemon.sh --ensure       (start if not running)
#              geo-daemon.sh --stop         (kill daemon)
#              geo-daemon.sh --toggle-geo   (toggle geometry restore, Super+F10)
#
# Coordinates in autofloat_positions.json are MONITOR-RELATIVE.
# Lookup order: class::title (per-window) > class (per-app)
#
# PERFORMANCE: All positions and exemptions are pre-cached into bash
# associative arrays at startup. Zero jq/process spawns per window event.
# Monitor geometry is cached and refreshed only on monitor change events.
#

PID_FILE="/tmp/hypr_geo_daemon.pid"
GEO_RESTORE_FILE="$HOME/.config/hypr/custom/.geo_restore_enabled"
MASTER_FLOAT_STATE="/tmp/hypr_master_float_state"
POS_FILE="$HOME/.config/hypr/custom/autofloat_positions.json"
EXEMPT_FILE="$HOME/.config/hypr/custom/autofloat_exemptions.txt"
DEFAULT_SIZE="1200 800"

get_socket2() {
    local sig="${HYPRLAND_INSTANCE_SIGNATURE}"
    if [ -z "$sig" ]; then
        sig=$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/" 2>/dev/null | head -1)
    fi
    echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${sig}/.socket2.sock"
}

daemon_alive() {
    [ -f "$PID_FILE" ] || return 1
    local pid
    pid=$(cat "$PID_FILE")
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && \
    [[ "$(ps -p "$pid" -o comm= 2>/dev/null)" == "bash" ]]
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && \
           [[ "$(ps -p "$pid" -o comm= 2>/dev/null)" == "bash" ]]; then
            local children
            children=$(ps --ppid "$pid" -o pid= 2>/dev/null)
            for cpid in $children; do
                kill "$cpid" 2>/dev/null
            done
            kill "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
}

# Check if any feature needs the daemon
any_feature_active() {
    [ -f "$GEO_RESTORE_FILE" ] || [ -f "$MASTER_FLOAT_STATE" ]
}

start_daemon() {
    stop_daemon

    local sock
    sock=$(get_socket2)

    if [ ! -S "$sock" ]; then
        notify-send "Geo Daemon" "Cannot find Hyprland socket: $sock"
        return 1
    fi

    nohup bash -c '
        sock="'"$sock"'"
        pos_file="'"$POS_FILE"'"
        geo_restore_file="'"$GEO_RESTORE_FILE"'"
        master_float_state="'"$MASTER_FLOAT_STATE"'"
        exempt_file="'"$EXEMPT_FILE"'"
        default_size="'"$DEFAULT_SIZE"'"

        # ── Pre-cached data structures ──
        declare -A pos_w pos_h pos_x pos_y
        declare -a exempt_class exempt_title
        declare -A monitor_cache
        declare -A monitor_name_to_id
        focused_monitor_id=""

        # Per-window tracking
        declare -A applied_keys
        declare -A addr_class

        # ── Cache loaders ──
        load_positions() {
            pos_w=(); pos_h=(); pos_x=(); pos_y=()
            [ ! -f "$pos_file" ] && return

            while IFS=$'"'"'\t'"'"' read -r key w h x y; do
                [ -z "$key" ] && continue
                pos_w["$key"]="$w"
                pos_h["$key"]="$h"
                pos_x["$key"]="$x"
                pos_y["$key"]="$y"
            done < <(jq -r "to_entries[] | \"\(.key)\t\(.value.w)\t\(.value.h)\t\(.value.x)\t\(.value.y)\"" "$pos_file" 2>/dev/null)
        }

        load_exemptions() {
            exempt_class=(); exempt_title=()
            [ ! -f "$exempt_file" ] && return

            while IFS= read -r pattern; do
                [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
                if [[ "$pattern" == title:* ]]; then
                    exempt_title+=("${pattern#title:}")
                else
                    exempt_class+=("$pattern")
                fi
            done < "$exempt_file"
        }

        load_monitors() {
            monitor_cache=()
            monitor_name_to_id=()
            focused_monitor_id=""
            local json
            json=$(hyprctl monitors -j 2>/dev/null)
            [ -z "$json" ] && return

            while IFS=$'"'"'\t'"'"' read -r mid mname mx my mw mh mfocused; do
                [ -z "$mid" ] && continue
                monitor_cache["$mid"]="$mx $my $mw $mh"
                [ -n "$mname" ] && monitor_name_to_id["$mname"]="$mid"
                [ "$mfocused" = "true" ] && focused_monitor_id="$mid"
            done < <(echo "$json" | jq -r ".[] | \"\(.id)\t\(.name)\t\(.x)\t\(.y)\t\(.width)\t\(.height)\t\(.focused)\"" 2>/dev/null)
        }

        # ── Load everything once at startup ──
        load_positions
        load_exemptions
        load_monitors

        # ── Pure-bash lookup (zero process spawns) ──
        lookup_geom() {
            local win_class="$1"
            local win_title="$2"

            if [ -n "$win_title" ]; then
                local key="${win_class}::${win_title}"
                if [ -n "${pos_w[$key]+set}" ]; then
                    printf "%s\t%s %s %s %s" "$key" "${pos_w[$key]}" "${pos_h[$key]}" "${pos_x[$key]}" "${pos_y[$key]}"
                    return 0
                fi
            fi

            if [ -n "$win_class" ] && [ -n "${pos_w[$win_class]+set}" ]; then
                printf "%s\t%s %s %s %s" "$win_class" "${pos_w[$win_class]}" "${pos_h[$win_class]}" "${pos_x[$win_class]}" "${pos_y[$win_class]}"
                return 0
            fi

            return 1
        }

        is_exempt() {
            local win_class="$1"
            local win_title="$2"
            local pat
            for pat in "${exempt_title[@]}"; do
                [[ "$win_title" =~ $pat ]] && return 0
            done
            for pat in "${exempt_class[@]}"; do
                [[ "$win_class" =~ ^${pat}$ ]] && return 0
            done
            return 1
        }

        get_focused_monitor_geom() {
            if [ -n "$focused_monitor_id" ] && [ -n "${monitor_cache[$focused_monitor_id]+set}" ]; then
                echo "${monitor_cache[$focused_monitor_id]}"
            else
                echo "0 0 1920 1080"
            fi
        }

        get_window_monitor_geom() {
            local addr="$1"
            local win_mon
            win_mon=$(hyprctl clients -j | jq -r --arg a "$addr" \
                ".[] | select(.address == \$a) | .monitor" 2>/dev/null)
            if [ -n "$win_mon" ] && [ "$win_mon" != "null" ] && [ -n "${monitor_cache[$win_mon]+set}" ]; then
                echo "${monitor_cache[$win_mon]}"
            fi
        }

        fetch_class_for_addr() {
            local addr="$1"
            hyprctl clients -j | jq -r --arg a "$addr" \
                ".[] | select(.address == \$a) | .class" 2>/dev/null
        }

        # Apply geometry with deferred resize to prevent transparent rendering.
        # Phase 1: float immediately (prevents tiling).
        # Phase 2: 50ms sleep lets Hyprland finish the initial surface commit,
        #          then resize/move/raise.
        apply_saved_geometry() {
            local addr="$1" w="$2" h="$3" rel_x="$4" rel_y="$5"
            local mon_x="$6" mon_y="$7"
            local gx=$(( rel_x + mon_x ))
            local gy=$(( rel_y + mon_y ))
            hyprctl dispatch setfloating "address:$addr" &>/dev/null
            {
                sleep 0.05
                hyprctl --batch \
                    "dispatch resizewindowpixel exact $w $h,address:$addr ; \
                     dispatch movewindowpixel exact $gx $gy,address:$addr ; \
                     dispatch alterzorder top,address:$addr" &>/dev/null
            } &
        }

        # ── Handle a window open event ──
        handle_window() {
            local addr="$1"
            local win_class="$2"
            local win_title="$3"

            read -r mon_x mon_y mon_w mon_h <<< "$(get_focused_monitor_geom)"

            # 1. Geometry restore (only when enabled)
            if [ -f "$geo_restore_file" ]; then
                result=$(lookup_geom "$win_class" "$win_title")
                if [ -n "$result" ]; then
                    IFS=$(printf "\t") read -r match_key geom <<< "$result"
                    read -r w h x y <<< "$geom"
                    apply_saved_geometry "$addr" "$w" "$h" "$x" "$y" "$mon_x" "$mon_y"
                    applied_keys["$addr"]="$match_key"
                    return 0
                fi
            fi

            # 2. Master-float (only when enabled)
            if [ -f "$master_float_state" ]; then
                if is_exempt "$win_class" "$win_title"; then
                    hyprctl dispatch setfloating "address:$addr" &>/dev/null
                    {
                        sleep 0.05
                        hyprctl dispatch alterzorder "top,address:$addr" &>/dev/null
                    } &
                else
                    read -r win_w win_h <<< "$default_size"
                    cx=$(( (mon_w - win_w) / 2 ))
                    cy=$(( (mon_h - win_h) / 2 ))
                    apply_saved_geometry "$addr" "$win_w" "$win_h" "$cx" "$cy" "$mon_x" "$mon_y"
                fi
                return 0
            fi

            return 1
        }

        socat -u "UNIX-CONNECT:$sock" - 2>/dev/null |
        while IFS= read -r line; do

            # ── openwindow>>ADDR,WORKSPACE,CLASS,TITLE ──
            if [[ "$line" == openwindow\>\>* ]]; then
                rest="${line#openwindow>>}"
                addr="0x${rest%%,*}"
                rest="${rest#*,}"
                rest="${rest#*,}"
                win_class="${rest%%,*}"
                win_title="${rest#*,}"

                # Deferred class resolution for empty-class windows
                if [ -z "$win_class" ]; then
                    win_class=$(fetch_class_for_addr "$addr")
                fi

                [ -n "$win_class" ] && addr_class["$addr"]="$win_class"

                handle_window "$addr" "$win_class" "$win_title"

            # ── windowtitlev2>>ADDR,NEWTITLE ──
            elif [[ "$line" == windowtitlev2\>\>* ]]; then
                # Only process if geometry restore is enabled
                [ ! -f "$geo_restore_file" ] && continue

                rest="${line#windowtitlev2>>}"
                raw_addr="${rest%%,*}"
                new_title="${rest#*,}"
                addr="0x${raw_addr}"

                [ -z "$new_title" ] && continue

                win_class="${addr_class[$addr]}"
                if [ -z "$win_class" ]; then
                    win_class=$(fetch_class_for_addr "$addr")
                    if [ -n "$win_class" ] && [ "$win_class" != "null" ]; then
                        addr_class["$addr"]="$win_class"
                    else
                        win_class=""
                    fi
                fi

                result=$(lookup_geom "$win_class" "$new_title")
                if [ -n "$result" ]; then
                    IFS=$(printf "\t") read -r match_key geom <<< "$result"
                    [ "${applied_keys[$addr]}" = "$match_key" ] && continue

                    read -r w h x y <<< "$geom"

                    read -r mon_x mon_y mon_w mon_h < <(get_window_monitor_geom "$addr")
                    if [ -z "$mon_x" ]; then
                        read -r mon_x mon_y mon_w mon_h <<< "$(get_focused_monitor_geom)"
                    fi

                    apply_saved_geometry "$addr" "$w" "$h" "$x" "$y" "$mon_x" "$mon_y"
                    applied_keys["$addr"]="$match_key"
                elif [ -z "${addr_class[$addr]}" ] && [ -n "$win_class" ]; then
                    addr_class["$addr"]="$win_class"
                    handle_window "$addr" "$win_class" "$new_title"
                fi

            # ── closewindow>>ADDR ──
            elif [[ "$line" == closewindow\>\>* ]]; then
                raw_addr="${line#closewindow>>}"
                addr="0x${raw_addr}"
                unset applied_keys["$addr"]
                unset addr_class["$addr"]

            # ── configreloaded>> ──
            elif [[ "$line" == configreloaded\>\>* ]]; then
                load_positions
                load_exemptions
                load_monitors

            # ── Monitor events ──
            elif [[ "$line" == monitoraddedv2\>\>* ]] || \
                 [[ "$line" == monitorremoved\>\>* ]]; then
                load_monitors

            # ── focusedmon>> ──
            elif [[ "$line" == focusedmon\>\>* ]]; then
                rest="${line#focusedmon>>}"
                mon_name="${rest%%,*}"
                if [ -n "${monitor_name_to_id[$mon_name]+set}" ]; then
                    focused_monitor_id="${monitor_name_to_id[$mon_name]}"
                fi

            fi
        done
    ' &>/dev/null &
    echo $! > "$PID_FILE"
    disown $!
}

ensure_daemon() {
    if ! daemon_alive; then
        start_daemon
    fi
}

# Stop daemon if no features need it
maybe_stop_daemon() {
    if ! any_feature_active && daemon_alive; then
        stop_daemon
    fi
}

# ── CLI interface ──
case "${1:-}" in
    --ensure)
        if any_feature_active; then
            ensure_daemon
        fi
        ;;
    --stop)
        stop_daemon
        ;;
    --toggle-geo)
        if [ -f "$GEO_RESTORE_FILE" ]; then
            # Turn OFF geometry restore
            rm -f "$GEO_RESTORE_FILE"
            maybe_stop_daemon
            notify-send "Hyprland" "📐 Geometry Restore: OFF"
        else
            # Turn ON geometry restore
            touch "$GEO_RESTORE_FILE"
            ensure_daemon
            notify-send "Hyprland" "📐 Geometry Restore: ON"
        fi
        ;;
    *)
        # Default: toggle geometry (backwards compat with keybind)
        exec "$0" --toggle-geo
        ;;
esac
