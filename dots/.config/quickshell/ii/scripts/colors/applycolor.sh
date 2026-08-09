#!/usr/bin/env bash

set -euo pipefail

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_DIR="$STATE_DIR/user/generated"
TERMINAL_DIR="$GENERATED_DIR/terminal"
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
COLORS_FILE="$GENERATED_DIR/material_colors.scss"

terminal_theming_enabled="true"
if [[ -f "$CONFIG_FILE" ]]; then
  apps_and_shell_enabled="$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell // true' "$CONFIG_FILE")"
  terminal_enabled="$(jq -r '.appearance.wallpaperTheming.enableTerminal // true' "$CONFIG_FILE")"
  if [[ "$apps_and_shell_enabled" != "true" || "$terminal_enabled" != "true" ]]; then
    terminal_theming_enabled="false"
  fi
fi

if [[ ! -s "$COLORS_FILE" ]]; then
  printf 'Generated color file is missing or empty: %s\n' "$COLORS_FILE" >&2
  exit 1
fi

mkdir -p "$TERMINAL_DIR"
kitty_theme_before=""
if [[ -r "$TERMINAL_DIR/kitty-theme.conf" ]]; then
  kitty_theme_before="$(sha256sum "$TERMINAL_DIR/kitty-theme.conf" | cut -d ' ' -f 1)"
fi
python3 "$SCRIPT_DIR/render_terminal_theme.py" \
  --colors "$COLORS_FILE" \
  --kitty-template "$SCRIPT_DIR/terminal/kitty-theme.conf" \
  --kitty-output "$TERMINAL_DIR/kitty-theme.conf" \
  --starship-template "$SCRIPT_DIR/terminal/starship.toml.in" \
  --starship-output "$TERMINAL_DIR/starship.toml" \
  --sequences-output "$TERMINAL_DIR/sequences.txt" \
  --enabled-file "$TERMINAL_DIR/enabled" \
  --enabled "$terminal_theming_enabled"
kitty_theme_after="$(sha256sum "$TERMINAL_DIR/kitty-theme.conf" | cut -d ' ' -f 1)"

# New Kitty processes read the persistent include at startup. Existing
# processes get a color-only remote-control update so runtime state such as
# per-window font size, scrollback, and layout is not reset on every palette
# adjustment. A full reload is reserved for disabling the include, where it is
# needed once to restore the user's base Kitty colors.
if [[ "$kitty_theme_before" != "$kitty_theme_after" ]]; then
  while read -r kitty_pid; do
    kitty_socket="unix:@kitty-${kitty_pid}.sock"
    if [[ "$terminal_theming_enabled" == "true" ]]; then
      if ! kitty @ --to "$kitty_socket" set-colors --all --configured "$TERMINAL_DIR/kitty-theme.conf"; then
        printf 'Could not update Kitty colors through %s\n' "$kitty_socket" >&2
      fi
    elif ! kill -USR1 "$kitty_pid" 2>/dev/null; then
      printf 'Could not reload Kitty process %s while disabling terminal colors\n' "$kitty_pid" >&2
    fi
  done < <(pgrep -u "$UID" -x kitty || true)
fi

# Other terminal emulators receive OSC colors only on their interactive shell
# PTYs. Kitty is deliberately skipped because its native include is persistent
# and atomic; writing blindly to every /dev/pts entry caused mixed palettes.
declare -A seen_ttys=()
while read -r shell_pid shell_tty shell_name; do
  case "$shell_name" in
    bash|dash|fish|nu|zsh) ;;
    *) continue ;;
  esac
  [[ "$shell_tty" == pts/* ]] || continue
  [[ -n "${seen_ttys[$shell_tty]:-}" ]] && continue

  shell_term="$(tr '\0' '\n' < "/proc/$shell_pid/environ" 2>/dev/null | sed -n 's/^TERM=//p' | head -n 1 || true)"
  case "$shell_term" in
    xterm-kitty|linux|dumb|'') continue ;;
  esac

  tty_path="/dev/$shell_tty"
  if [[ -w "$tty_path" ]]; then
    cat "$TERMINAL_DIR/sequences.txt" > "$tty_path" || true
    seen_ttys[$shell_tty]=1
  fi
done < <(ps -u "$UID" -o pid=,tty=,comm=)
