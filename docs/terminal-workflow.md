# Terminal workflow

Kitty handles local windows and rendering. tmux owns persistent workspaces and
supports ordinary SSH clients. zsh owns editing, history and prompt recovery.
Applications receive ordinary keyboard keys directly.

## Everyday keys and commands

| Action | Binding or command |
| --- | --- |
| Interrupt the foreground program | Ctrl+C |
| Copy Kitty selection | Ctrl+Shift+C |
| Search Kitty output | Ctrl+Shift+F |
| Kitty scrollback pager | Ctrl+Shift+H |
| Scroll Kitty history | Shift+Page Up / Shift+Page Down |
| Application navigation | Unmodified Page Up / Page Down and Ctrl+F |
| Global font zoom | Existing Ctrl+Plus / Minus / 0 |
| Current-window font zoom | Existing Ctrl+Shift or Ctrl+Alt zoom bindings |
| Search shell history | Ctrl+R; Up/Down substring search |
| Choose tmux workspace | `tw` (inside tmux opens its chooser) |
| Attach a named workspace | `tw NAME` |
| List workspaces | `tw list` |
| Capture the calling pane | `terminal-text` |
| Save that pane | `kdump [FILE]` |
| Copy that pane | `kclip` (Wayland locally; tmux clipboard over SSH) |
| tmux prefix / detach | Ctrl+B / Ctrl+B then D |
| tmux scrollback | Ctrl+B then `[` |
| Reload tmux configuration | Ctrl+B then Shift+R |

SSH clipboard delivery depends on the client's OSC 52 support; pane capture and
file saving do not. No shell startup automatically attaches to tmux or overrides
TERM. Mouse support remains enabled in tmux. Extended keys use negotiation rather
than being forced onto every client.

## Configuration ownership

- `.zshrc`: small entry point and deduplicated PATH.
- `.config/zsh/interactive.zsh`: history, completion, plugin order and prompt.
- `.config/zsh/terminal-recovery.zsh`: clears leftover mouse/focus and keyboard
  reporting when the shell regains its prompt, including after a TUI crash.
- `.config/zsh/terminal-tools.zsh`: captures explicitly target the calling pane.
- `.config/zsh/workflow.local.zsh`: optional host-only commands, intentionally
  absent from this public repository.
- `.config/zshrc.d/dots-hyprland.zsh`: generated wallpaper palette and Starship
  selection. Palette escapes are emitted only to a terminal.
- `.config/kitty/kitty.conf`: fonts, appearance, input and rendering settings.
- `.config/tmux/tmux.conf`: persistent tmux settings for local and SSH clients.

Optional helper files are sourced only when installed. The existing Codex-history
extension remains separate from personal history. Only SHARE_HISTORY writes and
imports personal shell history; its incompatible incremental options are off.
Leading-space commands are omitted from saved history.

Kitty keeps 50,000 interactive scrollback lines plus 64 MB of pager history per
window, allocated as needed. Existing windows retain their old history limits
until recreated. tmux keeps 50,000 lines for new panes; existing panes keep their
old allocation. These limits are not transcript backups. Rendering uses upstream
10 ms redraw / 3 ms input batching, with monitor synchronization enabled.

Kitty remote control uses its local socket. The search kitten, local control tools
and shell integration remain available; terminal output received over SSH does
not get unrestricted Kitty remote-control authority. Closing a busy window asks
for confirmation; idle shell windows can close normally.

## Dashboard input

`vminfo` discards SGR and legacy X10/VT200 mouse packets, focus reports, terminal
control strings and bracketed paste. A mouse coordinate is never decoded as an
action key. Its typed selectors and confirmations use the same event filtering.
Keyboard hotkeys, typed values and Unicode prompt text are preserved. This input
change does not alter process selection, action limits, warnings or confirmation
choices.

Run the collector-free regression suite:

```sh
python tests/test_terminal_input.py
# The same checks can be run against another compatible dashboard:
python tests/test_terminal_input.py /path/to/dashboard
```

The tests extract only input definitions; they do not import collectors or run
system/device actions. They cover fragmented packets and a real pseudo-terminal
prompt that rejects mouse/paste input while accepting typed text.

## Codex reboot restoration

The optional `restore-codex-tmux.py` helper uses a private, explicit manifest at
`~/.local/state/codex-tmux/restore.json`. Session IDs, working directories and
saved model/permission settings stay outside this repository. It opens the exact
existing thread with `codex resume`, gives the tmux session a brief name and adds
no follow-up prompt. Existing named tmux sessions are left alone. Failed Codex
startup leaves a shell available for recovery.

`--plan` prints the saved commands. `--test` uses an isolated tmux server with
inert shell placeholders and never launches Codex. Normal restoration is deferred
until the boot differs from the manifest's capture boot. The manifest is an
explicit snapshot, not automatic discovery of every new or completed task; review
it before future reboots. Restoration launch receipts do not prove successful
authentication, goal progress or device readiness.

## Validation and remaining manual checks

Validated on Kitty 0.49.1, zsh 5.9.2 and tmux 3.7c:

- Kitty parser and custom search-kitten import; no invalid wheel mappings.
- Full interactive zsh startup, repeated sourcing, Ctrl+R and history arrows.
- Personal/Codex history switching against isolated synthetic history files.
- Silent piped interactive startup and unchanged noninteractive output.
- Abrupt TUI exit recovery and preservation of tmux mouse support.
- 2,342 packet split cases plus a pseudo-terminal confirmation for the dashboard.
- An isolated reboot-restore layout with no agents started.

Manual acceptance: open a fresh local terminal and reconnect through the Android
SSH client; check editing, selection/copy, tmux detach/reattach, search and zoom.
After relaunching a dashboard, verify clicks/wheel have no dashboard effect and
keyboard hotkeys still work. The actual Android SSH client was not exercised by
the automated tests. Running Python processes must be relaunched to load changes.

Sources: [Kitty configuration](https://sw.kovidgoyal.net/kitty/conf/),
[Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
[zsh history options](https://zsh.sourceforge.io/Doc/Release/Options.html#History),
[XTerm input protocols](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
