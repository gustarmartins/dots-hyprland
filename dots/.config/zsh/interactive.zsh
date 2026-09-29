# Shared interactive setup for local terminals, tmux and SSH.
[[ -o interactive ]] || return 0

# SHARE_HISTORY already appends new commands; its incremental alternatives
# are mutually exclusive. Keep imported Codex history in its separate context.
if [[ ${CODEX_HISTORY_MODE:-zsh} != codex ]]; then
    HISTFILE="$HOME/.zsh_history"
    HISTSIZE=150000
    SAVEHIST=100000
    setopt APPEND_HISTORY SHARE_HISTORY EXTENDED_HISTORY
    setopt HIST_IGNORE_DUPS HIST_EXPIRE_DUPS_FIRST HIST_FIND_NO_DUPS
    setopt HIST_IGNORE_SPACE HIST_SAVE_BY_COPY
    unsetopt INC_APPEND_HISTORY INC_APPEND_HISTORY_TIME
fi

# Optional helpers must not break a shell on a different machine.
for _gus_helper in friendly hypr terminal-tools; do
    [[ -r "$HOME/.config/zsh/$_gus_helper.zsh" ]] && source "$HOME/.config/zsh/$_gus_helper.zsh"
done
unset _gus_helper

[[ -r "$HOME/.config/zshrc.d/dots-hyprland.zsh" ]] && source "$HOME/.config/zshrc.d/dots-hyprland.zsh"

# Agent commands using `zsh -ic` with pipes need no line editor or prompt.
if [[ -o zle && -t 0 && -t 1 ]]; then
    autoload -Uz compinit add-zsh-hook
    compinit
    _comp_options+=(globdots)
    bindkey -e

    for _gus_plugin in \
        /usr/share/fzf/key-bindings.zsh \
        /usr/share/fzf/completion.zsh \
        /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
        /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh; do
        [[ -r $_gus_plugin ]] && source "$_gus_plugin"
    done
    unset _gus_plugin
    if (( ${+functions[history-substring-search-up]} )); then
        bindkey '^[[A' history-substring-search-up
        bindkey '^[OA' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        bindkey '^[OB' history-substring-search-down
    fi
    bindkey '^[[1;5C' forward-word
    bindkey '^[[1;5D' backward-word
    bindkey '^[[H' beginning-of-line
    bindkey '^[OH' beginning-of-line
    bindkey '^[[F' end-of-line
    bindkey '^[OF' end-of-line
    bindkey '^[[3~' delete-char

    [[ -r "$HOME/.config/zsh/codex-history.zsh" ]] && source "$HOME/.config/zsh/codex-history.zsh"
    if (( ${+commands[starship]} )); then
        eval "$(starship init zsh)"
    else
        PROMPT='%F{cyan}%~%f %# '
    fi
    [[ -r "$HOME/.config/zsh/terminal-recovery.zsh" ]] && source "$HOME/.config/zsh/terminal-recovery.zsh"

    # Load after widgets and prompt hooks so highlighting sees their edits.
    [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
        source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
