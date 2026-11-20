# Codex notification expansion and session navigation

The notification center has an accented **•••** control, a hand cursor, a tooltip,
and a small hover bounce. It expands the notification without activating its
default action. Clicking the card invokes the default action when available;
right-clicking expands or collapses it. Group and individual expansion remain
separate. Expanded inbox text has no line-count cutoff.

## Why the old dots could not reveal more text

The installed Codex 0.169.0 sent observed terminal completion alerts as a
200-character summary ending in `...`, with an empty body. This was verified
from the notification history's lengths and empty-body fields, without reading
other conversations. Layout expansion cannot reconstruct the missing text.

Kitty's existing action can focus the originating live terminal, but its ordinary
OSC notification carries no durable Codex session/account identity. Saved alerts
also outlive the native sender and Quickshell reloads. Guessing by response text,
terminal titles, launch arguments, inherited terminal environment, or tmux names
would open the wrong task after a session switch or PID reuse.

The new integration uses Codex's documented `notify` JSON hook. It receives the
exact thread ID and full final assistant response. It sends the response as an
HTML notification body rendered from CommonMark and attaches an opaque
`x-mekki-codex` route token. Bold/italic emphasis, lists, links and code are
formatted; raw HTML stays escaped and images show their captions.
Input messages are never displayed or saved by the helper.

## Click behavior

| Current state | Behavior |
| --- | --- |
| Live Codex in Kitty | Focus the closest verified Kitty window; preserve the process and draft. |
| Live Codex in attached tmux | Select the exact window/pane and focus its Kitty attachment. |
| Detached tmux, including renamed sessions | Open Kitty attached to the existing tmux session; retain its writer. |
| Stopped session | Open Kitty and resume that exact UUID, original account home, current saved CWD, model and effort. No prompt or goal command is submitted. |
| Headless app-server with a verified Unix listener | Open a TUI against that server, rather than a second writer. The socket must belong to the actual writer PID. |
| Headless writer without an attachable server | Open a terminal that waits on its existing kernel writer lock. Resume only after the writer releases it. Closing the waiting terminal leaves the task running. |
| Repeated clicks during launch or background waiting | Reuse the waiting terminal or debounce the pending launch. |
| Shared daemon with inherited Kitty environment | Do not attribute its many threads to the terminal that originally launched the daemon. |
| Missing workspace, missing transcript, archived session, subagent, conflicting writers, or changed identity | Retain the alert and report why it could not open. Do not substitute another session. |

Routing is computed on demand from live PID/start identity, held writer locks,
controlling-terminal state, nearest terminal ancestry, and tmux/Kitty metadata.
No pane capture, transcript search, title matching, `send-keys`, `reptyr`, shared
server restart, or recurring polling is involved. Existing custom Kitty socket
names outside this workstation's `unix:@kitty-{kitty_pid}.sock` scheme are not
automatically discovered.

When a shared backend serves several TUI clients, this implementation cannot
prove which existing frontend currently displays a particular thread. It opens
another view of the same conversation through the verified server instead of
focusing an arbitrary window. This reuses the live backend, not a second agent.

The route registry contains account paths and UUIDs, not assistant text or
credentials. Notification history already stores notification text; it now also
stores the route token. This makes session actions survive sender exit and shell
reload. Route files are private and live outside the source tree.

## Controls and activation

Install `dots/.local/bin/codex-notify` to `~/.local/bin/codex-notify`, executable.
Dependencies: Python, `python-tomlkit`, `python-dbus`, `python-markdown-it-py`, SQLite, Kitty/kitten, tmux,
Quickshell, and `notify-send` for action-failure notices. No service is installed.

Super+I → **AI sessions** → **Codex session notifications** provides a master
switch and independent focus/reopen switches. Search terms include notifications,
ellipsis, terminal, detached, and resume.

```sh
codex-notify on
codex-notify status
codex-notify set focus off
codex-notify set reopen off
codex-notify off
```

Enabling installs the hook in the selected Codex home and removes only the native
turn-completion event from `tui.notifications`; approval alerts stay native. An
existing external `notify` command is retained and chained. Disabling restores
the prior values without overwriting later user changes, hides session actions,
and prevents a waiting terminal from resuming. Other source and settings remain
unchanged. Reopen Codex clients normally to load changed client settings; running
clients are never restarted by installation. Account switching does not rewrite
the account recorded in an existing notification.

Private local state:

- `~/.config/codex-notify/config.json`: switches and prior hook settings.
- `~/.local/state/codex-notify/routes/`: account/UUID route records.
- `~/.local/state/codex-notify/config-before.toml`: one private installation backup.
- Per-route lock/pending/viewer files: click serialization and PID birth fences.

`codex-notify plan TOKEN` reports a route without focusing or starting anything.
The native Codex writer lock remains the final fence against a concurrent resume.
The existing `codex-clean` launch gate is respected before stopped-session resume.

## Verification and limits

- `test_codex_notify.py`: configuration roundtrip, existing hooks, account
  isolation, exact resume arguments, missing data, renamed tmux, duplicate
  writers, shared-daemon attribution, nested terminals, headless jobs, and toggles.
- `quickshell_notification_ui.py`: real pointer input in private Xvfb/D-Bus,
  independent expansion, ellipsis hover, wrapped summaries, complete bodies
  longer than 24 lines, action callbacks, and card-click session routing.
- `quickshell_notification_integration.py`: the real JSON notifier and native
  Quickshell service, complete escaped response delivery, private input exclusion,
  durable actions across sender exit/reload, plus the existing lifecycle suite.
- `codex_notification_native.py`: real Kitty remote focus, actual detached tmux
  attachment, correct pane selection, repeated clicks, kernel-lock waiting,
  closing a waiting terminal, and master-off behavior with tiny synthetic writers.

The native tests use synthetic session metadata and lock holders. They do not
resume an authenticated real conversation or submit any model request. Actual
shared app-server attachment and automatic resume after a real background writer
finishes remain separate acceptance cases. Old Kitty alerts lack the missing
text and durable ID; the full-text/session-link behavior applies to new hook
notifications from clients that have loaded the configuration.

## Primary references

- [Codex advanced configuration: notifications](https://developers.openai.com/codex/config-advanced/#notifications)
- [Kitty notification protocol and activation](https://sw.kovidgoyal.net/kitty/desktop-notifications/#being-informed-when-user-activates-the-notification)
- [Kitty remote control](https://sw.kovidgoyal.net/kitty/remote-control/)
- [tmux manual](https://github.com/tmux/tmux/blob/master/tmux.1)

Behavior was also checked against installed `codex resume --help`, Kitty 0.50.0
Python notification code, and tmux 3.8 command definitions.
