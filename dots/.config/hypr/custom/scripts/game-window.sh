#!/usr/bin/env bash
set -euo pipefail

GAME_CLASSES="$HOME/.config/hypr/custom/game_classes.txt"

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
    hyprctl dispatch "hl.dsp.window.tag({ tag = \"$tag\", window = \"address:$addr\" })" >/dev/null
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

ensure_tag() {
    local tag="$1" label="$2" win addr cls tags
    win=$(active)
    addr=$(jq -r '.address // empty' <<<"$win")
    if [[ -z "$addr" ]]; then
        notify "$label" "no active window"
        return
    fi
    cls=$(jq -r '.class' <<<"$win")
    if has_tag "$tag" <<<"$win"; then
        tags=$(jq -r '.tags | join(" ") | if . == "" then "none" else . end' <<<"$win")
        notify "$label already ON — $cls" "tags: $tags"
        return
    fi
    hyprctl dispatch "hl.dsp.window.tag({ tag = \"+$tag\", window = \"address:$addr\" })" >/dev/null
    win=$(active)
    tags=$(jq -r '.tags | join(" ") | if . == "" then "none" else . end' <<<"$win")
    notify "$label ON — $cls" "tags: $tags"
}

cmd_game() {
    # F5 is intentionally idempotent: pressing it repeatedly must never
    # disable VRR eligibility for the focused game.
    ensure_tag gamemode "Game mode"
}

cmd_tear() {
    local state
    state=$(toggle_tag tearing "Tearing")
    if [[ "$state" == on && "$(hyprctl -j getoption general:allow_tearing | jq -r '.bool')" != true ]]; then
        notify "Tearing gate is OFF" "enable the QS tearing toggle (general:allow_tearing) for immediate mode to take effect"
    fi
}

cmd_persist() {
    local cls win
    cls=$(active | jq -r '.class // empty')
    if [[ -z "$cls" ]]; then
        notify "Game mode" "no active window"
        return
    fi
    touch "$GAME_CLASSES"
    if grep -qxF "$cls" "$GAME_CLASSES"; then
        grep -vxF "$cls" "$GAME_CLASSES" > "${GAME_CLASSES}.tmp" || true
        mv "${GAME_CLASSES}.tmp" "$GAME_CLASSES"
        hyprctl reload >/dev/null
        notify "Game mode rule removed" "$cls"
    else
        printf '%s\n' "$cls" >> "$GAME_CLASSES"
        hyprctl reload >/dev/null
        win=$(active)
        has_tag gamemode <<<"$win" || hyprctl dispatch "hl.dsp.window.tag({ tag = \"+gamemode\", window = \"address:$(jq -r '.address' <<<"$win")\" })" >/dev/null
        notify "Game mode rule saved" "$cls — full effect from next launch"
    fi
}

cmd_launch() {
    if [[ $# -eq 0 ]]; then
        notify "Game mode launch" "no command given"
        exit 1
    fi
    local quoted
    quoted=$(printf '%s' "$*" | jq -Rs .)
    hyprctl dispatch "hl.dsp.exec_cmd($quoted, { tag = \"+gamemode\" })" >/dev/null
    notify "Launching in game mode" "$*"
}

cmd_status() {
    local win mon fs present pid
    win=$(active)
    mon=$(hyprctl monitors -j | jq --argjson id "$(jq -r '.monitor' <<<"$win")" '[.[] | select(.id == $id)][0]')
    case "$(jq -r '.fullscreen' <<<"$win")" in
        2) fs=fullscreen ;;
        1) fs=maximized ;;
        0) fs=windowed ;;
        *) fs=unknown ;;
    esac
    pid=$(jq -r '.pid // empty' <<<"$win")
    present=unknown
    if [[ -n "$pid" && -r "/proc/$pid/environ" ]]; then
        present=$(tr '\0' '\n' <"/proc/$pid/environ" |
            sed -n 's/^MESA_VK_WSI_PRESENT_MODE=//p' | tail -1)
        present=${present:-app-default}
    fi
    notify "$(jq -r '.class' <<<"$win") — $fs" "$(printf '%s\n' \
        "tags: $(jq -r '.tags | join(" ") | if . == "" then "none" else . end' <<<"$win")" \
        "content: $(jq -r '.contentType' <<<"$win")   idle-inhibit: $(jq -r '.inhibitingIdle' <<<"$win")   xwayland: $(jq -r '.xwayland' <<<"$win")" \
        "$(jq -r '"[" + .name + "]  vrr: " + (.vrr|tostring) + "   tearing now: " + (.activelyTearing|tostring)' <<<"$mon")" \
        "present: $present   allow_tearing: $(hyprctl -j getoption general:allow_tearing | jq -r '.bool')   misc:vrr: $(hyprctl -j getoption misc:vrr | jq -r '.int')" \
        "tearing blocked: $(jq -r '(.tearingBlockedBy // []) | join(" ") | if . == "" then "clear" else . end' <<<"$mon")" \
        "solitary blocked: $(jq -r '(.solitaryBlockedBy // []) | join(" ") | if . == "" then "clear" else . end' <<<"$mon")" \
        "scanout blocked: $(jq -r '(.directScanoutBlockedBy // []) | join(" ") | if . == "" then "clear" else . end' <<<"$mon")")" 8000
}

case "${1:-status}" in
    game) cmd_game ;;
    tear) cmd_tear ;;
    persist) cmd_persist ;;
    launch) shift; cmd_launch "$@" ;;
    *) cmd_status ;;
esac
