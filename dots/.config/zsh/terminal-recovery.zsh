# A terminated TUI may leave mouse/focus reporting enabled. Reset only when
# the interactive shell owns the prompt; apps and tmux enable their own modes.
# Reset optional keyboard enhancements too; unsupported sequences are ignored.
# No tmux passthrough, screen clear, or input injection.
_gus_recover_terminal_prompt() {
    [[ -o interactive && -t 1 && ${TERM:-dumb} != dumb ]] || return 0
    printf '\033[?9;1000;1001;1002;1003;1004;1005;1006;1015;1016l\033[=0u\033[>4;0m'
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _gus_recover_terminal_prompt
add-zsh-hook precmd _gus_recover_terminal_prompt
