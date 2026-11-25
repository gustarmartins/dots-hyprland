# Recovery after a compositor crash

The `ii` shell supervisor resolves the current Hyprland instance for its Wayland
display before each launch. It retains the existing crash backoff and exits on a
clean shell shutdown. It does not select another display or nested compositor.

## Recovery after the session message bus dies

An OOM can kill `dbus-broker` while Quickshell survives. The panel and IPC can
still work, but its process-wide Qt D-Bus connection remains disconnected.
`Quickshell.reload(false)` preserves that connection, so a QML reload cannot
restore the tray, notifications or other session-bus services. Windscribe's
close-to-tray preference is additionally gated on Qt reporting an available
tray: a saved enabled preference alone does not prove the feature can work.

`SessionBusRecovery.qml` owns one `scripts/session_bus.py` child. The child
waits on the bus connection rather than polling memory, logs, apps or devices.
It reports the bus's `GetId` generation and whether this shell's tray host is
registered. The generation survives QML reloads. If the monitor itself is
killed, it reconnects with backoff; the same bus generation leaves the shell
alone. A replaced bus or a shell absent from the current bus triggers a normal
shell exit with status 75, after the replacement bus is reachable. Existing destruction handlers save state and stop owned children; the existing
supervisor relaunches the shell. It also waits for a real bus before future
shell launches, avoiding a cached disconnected Qt connection during startup.
Explicit clean quit still stops the supervisor. The monitor disappears with its
owning shell.

While `GlobalStates.screenLocked` is active (`WlSessionLock` holds
`ext_session_lock_v1`), destructive recovery and reload paths must not tear down
the lock client or Hyprland enters its crashed-lockscreen fallback.
`SessionBusRecovery` defers its exit-75 restart (`state: "deferred"`,
`deferred: true`), `ShellControl` (`shellControl.reload` and
`shellControl.restartForUpdate`) defers in-place QML reloads and update
restarts, and `panelFamily` cycling is ignored while locked. Once the screen
unlocks, pending reload or restart actions run after a short post-unlock settle
delay (300 ms) so `unlock_and_destroy` and lock-screen workspace restoration
flush cleanly first; re-locking during that window re-defers the action.

```sh
qs -c ii ipc call sessionBus status
qs -c ii ipc call shellControl status
```

This repairs the shell's connection, not another application's private Qt
connection. A surviving Qt tray app can re-register after only the tray host
restarts, but a Qt app that survived the entire bus being replaced may itself
need reopening. Do not silently kill Windscribe or cycle a live VPN to repair
an icon. This recovery changes no VPN settings, firewall, OOM scoring, swap
policy or user-selected memory protection. It does not prevent an OOM.

The system Python dependency is `python-dbus-fast`, included in the Arch
dependency package. The private lifecycle regression additionally requires
Xvfb, `dbus-daemon`/`busctl`, PySide6, and the installed Quickshell:

```sh
python3 tests/quickshell_session_bus_lifecycle.py
```

It checks bus-unavailable startup, QML reloads, monitor SIGKILL, shell SIGKILL,
tray re-registration and actual fixture hide-to-tray behavior, bus replacement
while the monitor also dies, new Qt clients on the recovered bus, one monitor
per shell, and explicit quit without respawn. Its bus, display, home and config
are private; it neither exhausts memory nor restarts the desktop's real bus.

Relevant upstream code: [Quickshell's process-wide tray watcher](https://github.com/quickshell-mirror/quickshell/blob/5d5d498/src/services/status_notifier/watcher.cpp),
[Qt's disconnected-connection lifetime](https://doc.qt.io/qt-6/qdbusconnection.html#details),
and [Windscribe's tray availability gate](https://github.com/Windscribe/Desktop-App/blob/master/src/client/frontend/frontend-common/backend/preferences/preferences.cpp).

## Clipboard and workspace recovery

Clipboard capture belongs to the shell's `Cliphist` service. `Cliphist.start()`
starts one text watcher and one image watcher; Quickshell owns both processes and
recreates them on shell restart or QML reload. A watcher that exits independently
retries after two seconds. Clipboard contents go directly into the existing
`~/.local/bin/cliphist` wrapper and database; only a completion marker returns to
QML to refresh the history model. Opening settings alone does not start capture.
The former Hyprland login commands are removed to avoid duplicate watchers.

Inspect capture without printing clipboard contents:

```sh
qs -c ii ipc call cliphistService status
```

`workspaces.lua` retains the existing numbered workspace mapping: each group of
ten places its first five workspaces on `DP-1` and its second five on `HDMI-A-1`.
After config load or a monitor layout change, a single deferred pass moves any
existing numbered workspace that disagrees with that map. This covers fallback
workspaces created before the normal config loads. Missing/disabled outputs,
mirrors, named workspaces and special workspaces are skipped. Reconnecting an
output retries restoration through the monitor event; there is no polling.
Native workspace moves retain windows and leave an unrelated focused workspace
alone. Manual workspace moves are not continuously overridden; loading the
saved config or changing the monitor layout reapplies the saved assignment.

Isolated regression checks use private Wayland displays, D-Bus sessions, homes,
and clipboard databases. They never crash or manipulate the live desktop:

```sh
python3 tests/test_qs_respawn.py
dbus-run-session -- python3 tests/quickshell_clipboard_lifecycle.py
dbus-run-session -- python3 tests/hyprland_workspace_recovery.py
```

The clipboard test covers text/image storage and decode, model refresh, three
QML reloads without duplicate watchers, watcher failure, compositor loss and
restart, retained history, and clean shutdown. The workspace test covers loading
normal rules after fallback placement, foreground/window preservation, repeated
reloads, a missing output, and reconnection. Dependencies are KWin Wayland,
Hyprland with Lua, Quickshell, wl-clipboard, cliphist, Kitty, Python/Pillow, and
the existing Bash/jq/timeout supervisor dependencies.
