# CryoD session integration

Super+I → CryoD also has **Group new launcher apps**. With the master enabled,
this choice defaults On and routes new nonterminal entries/actions through
`/usr/local/libexec/cryod-desktop/cryod-app-launch` (alpha31). It groups only the
new launch for Focus Mode; an already running instance keeps its current group.
It does not enable app freezing. Turning the choice or master Off uses the
ordinary launch route and starts no watcher. Existing app processes keep running.

Parsed arguments, working directory and environment are preserved. Missing helper
or manager falls back to the original command once. App exit codes never trigger
another launch. Build-quota groups are retained; terminal commands keep their
existing route. `cryod.groupLaunches` persists through the same Config writer as
the other choices. The searchable destination includes application launch groups.
Validation: `python3 tests/cryod_app_launch.py /path/to/cryod-app-launch` plus the
existing private-display `cryod_settings_ui.py` and `settings_catalog.py` tests.

Super+I → CryoD provides the session master switch and independent protection
for the focused app tree and other visible windows. The default is Off. Enabling
it requires the separately installed CryoD desktop service and
`/usr/local/libexec/cryod-desktop/cryod-session-bridge` (alpha7 or later).

The main shell owns one bridge; settings windows only edit preferences and read
status. Existing Hyprland models provide focus/window/workspace/monitor changes.
No shell is launched per event. Five-second snapshots renew a fifteen-second
lease; the native daemon verifies UID and PID birth. The bridge sends no titles,
command lines, documents or keyboard input. Reconnect sends a full snapshot.

Master Off sends a bounded release request and stops the bridge and its timers.
It does not stop the memory daemon. The feature controls hide while Off. A lost
connection is reported as unknown; the daemon retains its enabled intent and
blocks ordinary signals until session knowledge is restored or Off is confirmed.
Independent emergency runaway protection keeps its own permission and evidence
requirements. Window PID/descendant protection is implemented; shared terminal
pane grouping and automatic prefetch remain with the native port workstream.

`cryod.enabled`, `cryod.protectForeground` and `cryod.protectVisible` are preserved
through the existing Config writer. `cryodSession status` is a read-only IPC
endpoint. The root lease is `/run/cryod/focus.json`. This integration does not
change VM Atlas helpers, services or publication.

Private verification:

```sh
python3 tests/settings_catalog.py
python3 tests/cryod_session.py /path/to/cryod-desktop
xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python3 tests/cryod_settings_ui.py
```

The session test uses disposable processes and a private native observer. The
settings test uses a disposable home, X display and D-Bus session. Neither test
changes the owner's foreground window or memory policy.
