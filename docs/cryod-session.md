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

## App preferences and Yes/No actions — source qualification

The new `CryoDConsent.qml` client and Super+I app-preference rows are qualified in
private fixtures, **not installed**. They require the matching native
`application-consent` API and `cryod-control-client`, plus `notify-send` and
`gdbus`. Existing desktop integration settings keep their current values.

Refresh reads verified running launcher apps and saved app choices. Choose asks
the native owner for an expiring app/instance/policy-bound offer, then presents
Yes and No through Quickshell's notification server. Yes explicitly allows
observation/freezing; No saves freezing/recommendation denial. Dismissal grants
nothing. The shell shows Saved only after the native receipt confirms its exact
policy revision is adopted. Unknown transport completion queries that receipt
once instead of repeating a decision. Stale pages/offers cannot silently select
a different app. Saved denials remain visible after the app exits; changing a
choice currently requires a verified running instance.

Master Off closes this client's notification and stops its request/prompt
processes. It preserves saved choices and does not undo a decision already sent;
the next refresh reads native state. Notifications use the owner's ordinary
popup timeout, with a separate offer-expiry bound. Missing helpers/failed requests
have a finite cleanup path. No periodic app observer is started by this manual
flow, and no client writes policy files, CPU quotas or cgroup freezer values.

`tests/cryod_consent.py PACKAGE APPLICATION_TESTS` exercises the actual QML,
notify-send actions, private Quickshell notification server and native receipts.
Six groups cover dismissal, Yes, No, Off, missing-helper recovery and a closed-app
denial. The settings fixture renders an app row using a private catalog helper;
it never connects to the owner's native socket. Existing settings persistence and
the299-key catalog check pass. This is not automatic suggestion production,
ordinary GUI freezer qualification, or an installed feature. Those remain with
the native desktop goal before versioned delivery; VM Atlas publication stays
separate.
