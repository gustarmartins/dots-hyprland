#!/usr/bin/env bash
set -euo pipefail

GEN_RULES="$HOME/.config/hypr/custom/generated_game_rules.conf"

notify() {
    notify-send -a Hyprland -t "${3:-3000}" "$1" "$2"
}

active() {
    hyprctl activewindow -j
}

has_tag() {
    jq -e --arg t "$1" 'any(.tags[]; . == $t or . == ($t + "*"))' >/dev/null
}

toggle_tag() {
    local tag="$1" label="$2" win addr cls tags
    addr=$(active | jq -r '.address // empty')
    if [[ -z "$addr" ]]; then
        notify "$label" "no active window"
        echo off
        return
    fi
    hyprctl dispatch tagwindow "$tag" "address:$addr" >/dev/null
    win=$(active)
    cls=$(jq -r '.class' <<<"$win")
    tags=$(jq -r '.tags | join(" ") | if . == "" then "none" else . end' <<<"$win")
    if has_tag "$tag" <<<"$win"; then
        echo on
        notify "$label ON — $cls" "tags: $tags"
    else
        echo off
        notify "$label OFF — $cls" "tags: $tags"
    fi
}

cmd_game() {
    toggle_tag gamemode "Game mode" >/dev/null
}

cmd_tear() {
    local state
    state=$(toggle_tag tearing "Tearing")
    if [[ "$state" == on && "$(hyprctl -j getoption general:allow_tearing | jq -r '.int')" != 1 ]]; then
        notify "Tearing gate is OFF" "enable the QS tearing toggle (general:allow_tearing) for immediate mode to take effect"
    fi
}

cmd_persist() {
    local cls esc line win
    cls=$(active | jq -r '.class // empty')
    if [[ -z "$cls" ]]; then
        notify "Game mode" "no active window"
        return
    fi
    esc=$(printf '%s' "$cls" | sed -E 's/[][^$.|?*+(){}\\]/\\&/g')
    line="windowrule = match:class ^(${esc})\$, tag +gamemode"
    touch "$GEN_RULES"
    if grep -qxF "$line" "$GEN_RULES"; then
        grep -vxF "$line" "$GEN_RULES" > "${GEN_RULES}.tmp" || true
        mv "${GEN_RULES}.tmp" "$GEN_RULES"
        hyprctl reload config-only >/dev/null
        notify "Game mode rule removed" "$cls"
    else
        printf '%s\n' "$line" >> "$GEN_RULES"
        hyprctl reload config-only >/dev/null
        win=$(active)
        has_tag gamemode <<<"$win" || hyprctl dispatch tagwindow +gamemode "address:$(jq -r '.address' <<<"$win")" >/dev/null
        notify "Game mode rule saved" "$cls — full effect from next launch"
    fi
}

cmd_launch() {
    if [[ $# -eq 0 ]]; then
        notify "Game mode launch" "no command given"
        exit 1
    fi
    hyprctl dispatch exec -- "[tag +gamemode] $*" >/dev/null
    notify "Launching in game mode" "$*"
}

cmd_status() {
    local win mon fs
    win=$(active)
    mon=$(hyprctl monitors -j | jq '[.[] | select(.focused)][0]')
    case "$(jq -r '.fullscreen' <<<"$win")" in
        2) fs=fullscreen ;;
        1) fs=maximized ;;
        0) fs=windowed ;;
        *) fs=unknown ;;
    esac
    notify "$(jq -r '.class' <<<"$win") — $fs" "$(printf '%s\n' \
        "tags: $(jq -r '.tags | join(" ") | if . == "" then "none" else . end' <<<"$win")" \
        "content: $(jq -r '.contentType' <<<"$win")   idle-inhibit: $(jq -r '.inhibitingIdle' <<<"$win")   xwayland: $(jq -r '.xwayland' <<<"$win")" \
        "$(jq -r '"[" + .name + "]  vrr: " + (.vrr|tostring) + "   tearing now: " + (.activelyTearing|tostring)' <<<"$mon")" \
        "allow_tearing: $(hyprctl -j getoption general:allow_tearing | jq -r '.int')   misc:vrr: $(hyprctl -j getoption misc:vrr | jq -r '.int')" \
        "tearing blocked: $(jq -r '.tearingBlockedBy | join(" ") | if . == "" then "clear" else . end' <<<"$mon")" \
        "solitary blocked: $(jq -r '.solitaryBlockedBy | join(" ") | if . == "" then "clear" else . end' <<<"$mon")" \
        "scanout blocked: $(jq -r '.directScanoutBlockedBy | join(" ") | if . == "" then "clear" else . end' <<<"$mon")")" 8000
}

case "${1:-status}" in
    game) cmd_game ;;
    tear) cmd_tear ;;
    persist) cmd_persist ;;
    launch) shift; cmd_launch "$@" ;;
    *) cmd_status ;;
esac
