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

`vminfo` consumes SGR and legacy X10/VT200 mouse packets, focus reports, terminal
control strings and bracketed paste. SGR wheel events become navigation events;
a mouse coordinate is never decoded as an
action key. Its typed selectors and confirmations use the same event filtering.
Keyboard hotkeys, typed values and Unicode prompt text are preserved. This input
change does not alter process selection, action limits, warnings or confirmation
choices.

Press `m` to freeze the process snapshot and enter the process manager. Arrow
keys, `j`/`k`, page keys and the mouse wheel navigate; Space marks a process,
`/` searches, and `i` inspects it. Explicit force-swap, unswap and signal actions
retain their confirmation flow and validate process identity before acting.
Leaving the manager restores the prior pause state.

Run the collector-free regression suite:

```sh
python tests/test_terminal_input.py
# The same checks can be run against another compatible dashboard:
python tests/test_terminal_input.py /path/to/dashboard
```

The tests extract only input definitions; they do not import collectors or run
system/device actions. They cover fragmented packets and a real pseudo-terminal
prompt that rejects mouse/paste input while accepting typed text.

## Manual Codex restoration

The optional `restore-codex-tmux.py` helper uses a private, explicit manifest at
`~/.local/state/codex-tmux/restore.json`. Session IDs, working directories and
saved settings stay outside this repository. Manual recovery requires `--now`;
invocation without that flag does not restore sessions at login or boot. The
helper reads each selected thread's current working directory, model, reasoning
and permissions from the local state database, then resumes that exact thread.
An explicitly saved continuation prompt is optional. Existing writers and live
or unrelated tmux panes are left alone. A failed launch remains a dead pane;
only the same owned pane from the same boot can be retried after a nonzero exit.

`--plan` prints the saved commands. `--test` uses an isolated tmux server with
inert shell placeholders and never launches Codex. The manifest is an explicit
snapshot, not automatic discovery of every new or completed task; review it
before requesting recovery. Writer-lock verification establishes process
ownership, not successful authentication, goal progress or device readiness.

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
keyboard hotkeys still work. The initial dashboard tests did not exercise the Android SSH client; the
Haven-specific test below covers the Codex terminal path separately. Running Python processes must be relaunched to load changes.

Sources: [Kitty configuration](https://sw.kovidgoyal.net/kitty/conf/),
[Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
[zsh history options](https://zsh.sourceforge.io/Doc/Release/Options.html#History),
[XTerm input protocols](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).

## Metered connections

New dashboard launches default to low-data operation: host samples every five
seconds; Android metrics every five seconds and its process list every fifteen.
Only changed rows are written, and identical/paused frames write nothing. Input
is checked at most 200 ms apart while waiting between samples, so the sampling
interval does not impose a five-second delay on keyboard navigation. Collectors
can still take time independently. `--fast` restores the previous sampling rates;
`--low-data` documents the default explicitly. The scripts do not detect whether
the remote phone is on LTE or Wi-Fi.

The tmux status interval is 60 seconds. This only changes the status bar; it is
not an output cap for running programs. Existing history buffers are local data
and are not continuously transmitted just because they are large.

For mobile sessions, prefer one connected SSH terminal and use Ctrl+B then S to
switch tmux sessions. Detach or disconnect unneeded terminals rather than leaving
several live streams attached. tmux work survives detachment. The current Haven
SSH reader continues reading while its channel remains connected; changing
Android screen rendering alone is not a reliable network-saving mechanism.

On this host, Codex's `tui.animations` is disabled for its next launch. Its existing
status fields are preserved. Existing dashboard/Codex processes need reopening
to load their new configuration; no running tasks were restarted by this change.

`tests/test_dashboard_render.py` verifies unchanged output, one-row changes,
resize, shortened content and return from action screens. Its 40-row synthetic
minute changed four rows every five seconds: 1,393,800 old full-redraw bytes versus
10,823 incremental bytes. These are application-output bytes under a constructed
workload, **not a Haven/LTE measurement or a guaranteed percentage reduction**.

The host has mosh-server installed, and Haven documents Mosh support. It is an
optional transport to evaluate later, not a configuration change made here. SSH
compression must be negotiated by the phone's client; changing this PC's outbound
SSH client settings cannot enable it for an inbound Haven connection.

References: [Haven terminal documentation](https://github.com/GlassHaven/Haven/blob/main/docs/features/terminal.md),
[Haven SSH reader](https://github.com/GlassHaven/Haven/blob/main/core/ssh/src/main/kotlin/sh/haven/core/ssh/TerminalSession.kt),
[OpenAI animation setting](https://learn.chatgpt.com/docs/config-file/config-reference).

## Haven: one terminal tab and SSH compression

Haven supports custom toolbar buttons. Keep its existing connection profiles and
native tmux manager; connect to one session, then switch sessions within that
same tab using these custom send strings (JSON escapes shown):

| Button | Send | Effect |
| --- | --- | --- |
| Sessions | `\u0002s` | Static tmux session chooser |
| Prev | `\u0002(` | Previous session |
| Next | `\u0002)` | Next session |
| Hold | `\u0002[` | Read a held history view; work continues |
| Live | `\u0002\u001b[F` | Leave history and redraw latest output |

Keep the original toolbar keys. Haven's aligned layout only renders two rows;
prepend these buttons to the first existing row, rather than adding a third row.
Set “terminal tab titles follow session” off to display the current tmux title
when switching inside a single SSH tab. Disconnect surplus existing Haven tabs:
hiding an Android tab does not stop its SSH reader.

For this workstation's connection profiles, Advanced SSH options can negotiate
post-authentication compression with the JSch engine:

```text
compression.s2c zlib@openssh.com,none
compression.c2s zlib@openssh.com,none
compression_level 6
zlib@openssh.com com.jcraft.jsch.juz.Compression
```

The JDK compression implementation is bundled in the tested Haven APK. `none`
remains a fallback. The server must allow compression; this host already did.
Authentication, host verification, encryption, terminal colors and functions
remain in place. These options are specific to JSch; do not assume another SSH
engine honors them. Existing native tmux profiles retain their original startup
commands and session-manager mode. The optional `tmux-phone` host command opens
a lobby/chooser, but replacing a Haven profile with a plain SSH RemoteCommand
would bypass native manager shortcuts, so that replacement is not the default.

Measured on Haven 5.89.0 over a real SSH connection to tmux and a resumed Codex
TUI, with client/server compression proposals captured: 20 transcript/navigation
cycles took 29.2 seconds. Without compression, TCP acknowledged 347,216 SSH
payload bytes; with compression, 22,280 bytes (93.6% less). An earlier compressed
repeat measured 23,376 bytes. A 31-second idle sample sent 120 bytes; navigating
the hidden Codex session while the same client viewed another tmux session sent
72 bytes over 29.3 seconds. The test used Wi-Fi transport to isolate the same SSH
payload carried over LTE; it does not measure carrier billing, tunnel overhead,
all Haven features or a sustained model/tool streaming workload.

For live app-data maintenance, Haven's notification listener can restart the app
immediately after force-stop. Verify the process is actually stopped before
backing up or editing its database. Preserve the listener component's prior
state, database WAL, app UID/mode/SELinux labels, credentials and unknown fields;
restore the component after the brief transaction. Prefer supported UI settings
for ordinary future edits.

Source inspected: [Haven v5.89.0](https://github.com/GlassHaven/Haven/tree/v5.89.0),
with relevant schema/options checked against v5.89.14; JSch 2.28.7.

## Clipboard after a boot-time tmux restore

The persistent tmux server can start before Hyprland imports DISPLAY and
WAYLAND_DISPLAY. Restored Codex processes then cannot find the desktop clipboard.
The restore helper now waits up to 30 seconds for a valid local desktop socket,
imports only the display/runtime variables, and still permits headless startup.
It does not change the environment of already-running applications.

For restored Codex sessions in local Kitty, Ctrl+V uses `codex-paste-image` to
read a Wayland PNG/JPEG/WebP into a private cache and bracket-paste its path.
Codex recognizes that as an image attachment, matching file drag-and-drop.
The prompt is not submitted and its existing text is preserved. The helper checks
the actual foreground process, so manually opened Codex panes work without a
restoration tag. Non-Codex processes and SSH/Haven clients receive ordinary Ctrl+V.
Ctrl+Shift+V uses Kitty text paste and also attaches image clipboards in local Codex, as described below. Cached images remain under
`~/.cache/codex-clipboard/` so a pending attachment remains available.

The installed Codex 0.158.0 recognized a fixture through this path as [Image #1]
in an isolated frontend; no prompt was submitted. Wayland clipboard type discovery
was checked live. The user's screenshot had been replaced with text by test time,
so the next screenshot's direct Ctrl+V remains a user acceptance check.

Reference: [OpenAI image drag-and-drop workflow](https://learn.chatgpt.com/docs/prompting).

## Direct Kitty versus tmux: clipboard follow-up

Identify the particular terminal using its live process ancestry and environment.
The presence of other tmux sessions on the host does not put a direct Kitty Codex
window inside tmux. Both were present during qualification.

Ctrl+Shift+V invokes `codex_paste.py`. Ctrl+V invokes its image-only mode, which
attaches images in local Codex and otherwise sends the original key to the app.
Both routes read the clipboard from Kitty's desktop environment, even if an
existing Codex process started before the desktop. Text retains Kitty's native paste path,
including bracketed paste and control-character confirmation. An image clipboard
in a direct Codex or local tmux Codex terminal is copied to a private image file
and attached by pasting its path. No Enter is generated. Native direct Codex
Ctrl+V also successfully attached the live PNG during testing.

The stock Kitty paste action read text only when application paste events were
disabled: with an image/png-only clipboard it delivered zero bytes. The custom
shortcut fixes that reproduced image case. The earlier reported plain-text
failure was not reproduced: controlled multiline Unicode text reached both
Codex frontends and preserved drafts. No unsupported text-failure cause is claimed.

Detection uses foreground process names and ancestry and, for tmux, its
client-to-active-pane mapping. An update can leave a running executable linked as
`codex (deleted)` in `/proc`; this does not prevent image paste or require a restart.
Kitty can report an empty foreground process list for a tmux client, so its live
child PID is also checked. Codex must be in the terminal foreground process group;
a background Codex child must not intercept another program's input. Remote SSH
windows and Haven Android do not acquire the host's clipboard through this Kitty
shortcut. This follow-up makes no Android configuration changes.

Verification used disposable direct Kitty and local tmux Codex frontends, the
actual image clipboard, the loaded Ctrl+Shift+V mapping, and controlled multiline
Unicode text. Drafts survived, image tokens appeared, and no test prompt was
submitted. The user's clipboard was not replaced. No active peer was interrupted.
Source: [Kitty clipboard actions](https://sw.kovidgoyal.net/kitty/actions/).

October 10 regression checks on Codex 0.162.1 reproduced Ctrl+V failure in a
disposable tmux pane without DISPLAY, WAYLAND_DISPLAY or a restoration tag.
The corrected tmux binding and both Kitty actions attached the actual PNG as
`[Image #N]`, preserving a Unicode draft without submitting it. Multiline text
paste and ordinary Ctrl+V in a non-Codex process also passed. Running Codex
processes whose executable had been replaced were correctly recognized.

## Route labels and quiet counters

Every Kitty window now has a persistent title row: [DIRECT], [TMUX], or [SSH],
followed by its existing task/application title. It uses the terminal's live
foreground process group, including tmux started through an existing shell;
other tmux sessions merely existing on the host do not change the label.
Tmux's status bar also displays [TMUX]. These markers are local rendering and
add no periodic SSH traffic beyond the existing status refresh.

A static Codex Working counter alone does not mean a stalled task. The low-data
animation setting remains off. In the qualified sample, tmux and Kitty held the
same static counter while broader event samples showed actual work progressing.
No compositor policy or peer lifecycle change was justified. Check current pane
contents and substantive session events; treat completed turns, input waits,
network/tool waits and genuinely suspended processes separately.
