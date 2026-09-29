# Capture the calling pane rather than whichever window happens to be focused.
unalias kclip KCLIP KDUMP 2>/dev/null || true

terminal-text() {
    if [[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]]; then
        command tmux capture-pane -p -S - -t "$TMUX_PANE"
    elif [[ -n ${KITTY_WINDOW_ID:-} ]]; then
        command kitty @ get-text --match "id:$KITTY_WINDOW_ID" --extent all
    else
        print -u2 'terminal-text: use this inside Kitty or tmux'
        return 1
    fi
}

kclip() {
    local contents
    contents=$(terminal-text) || return
    if [[ -n ${WAYLAND_DISPLAY:-} && -z ${SSH_CONNECTION:-} ]] && (( ${+commands[wl-copy]} )); then
        print -r -- "$contents" | command wl-copy
    elif [[ -n ${TMUX:-} ]]; then
        print -r -- "$contents" | command tmux load-buffer -w -
    else
        print -u2 'kclip: no local Wayland clipboard or tmux clipboard available; use kdump'
        return 1
    fi
}

kdump() {
    local out=${1:-$HOME/terminal-$(date +%Y%m%d-%H%M%S).txt} contents
    contents=$(terminal-text) || return
    (umask 077; print -r -- "$contents" >| "$out") && print -r -- "Saved: $out"
}
alias KCLIP=kclip KDUMP=kdump

# No automatic attachments during shell startup; safe with SSH and nested shells.
tw() {
    if [[ ${1:-} == list ]]; then
        command tmux list-sessions
    elif [[ -n ${TMUX:-} ]]; then
        if [[ -n ${1:-} ]]; then
            command tmux switch-client -t "=$1"
        else
            command tmux choose-tree -s
        fi
    elif [[ -n ${1:-} ]]; then
        command tmux attach-session -t "=$1"
    elif command tmux has-session 2>/dev/null; then
        command tmux attach-session
    else
        command tmux new-session -s work
    fi
}
