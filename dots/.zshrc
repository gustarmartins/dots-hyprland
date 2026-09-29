# Interactive terminal configuration; personal helpers stay on this host.
[[ -o interactive ]] || return 0

typeset -U path PATH
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
path=("$HOME/.local/bin" "$HOME/.cargo/bin" "$PNPM_HOME" $path)
export PATH

[[ -r "$HOME/.config/zsh/workflow.local.zsh" ]] && source "$HOME/.config/zsh/workflow.local.zsh"
source "$HOME/.config/zsh/interactive.zsh"
