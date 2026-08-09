# Use the generated color scheme without redefining xterm's 16-255 indexes.
ii_terminal_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/terminal"
if [[ -r "$ii_terminal_dir/enabled" && "$(<"$ii_terminal_dir/enabled")" == "true" ]]; then
    [[ -r "$ii_terminal_dir/sequences.txt" ]] && cat "$ii_terminal_dir/sequences.txt"
    [[ -r "$ii_terminal_dir/starship.toml" ]] && export STARSHIP_CONFIG="$ii_terminal_dir/starship.toml"
elif [[ "${STARSHIP_CONFIG:-}" == "$ii_terminal_dir/starship.toml" ]]; then
    unset STARSHIP_CONFIG
fi
unset ii_terminal_dir
