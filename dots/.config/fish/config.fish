# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    set -l ii_terminal_dir "$XDG_STATE_HOME/quickshell/user/generated/terminal"
    if test -z "$XDG_STATE_HOME"
        set ii_terminal_dir "$HOME/.local/state/quickshell/user/generated/terminal"
    end
    if test -r "$ii_terminal_dir/enabled"; and test (string trim < "$ii_terminal_dir/enabled") = true
        set -gx STARSHIP_CONFIG "$ii_terminal_dir/starship.toml"
    else if set -q STARSHIP_CONFIG; and test "$STARSHIP_CONFIG" = "$ii_terminal_dir/starship.toml"
        set -e STARSHIP_CONFIG
    end
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors
    if test -r "$ii_terminal_dir/enabled"; and test (string trim < "$ii_terminal_dir/enabled") = true; and test -r "$ii_terminal_dir/sequences.txt"
        cat "$ii_terminal_dir/sequences.txt"
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    if test "$TERM" != "linux"
        alias ls 'eza --icons'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end
