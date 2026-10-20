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

## App preferences and Yes/No actions — local delivery, October20

The `CryoDConsent.qml` client and Super+I app-preference rows are installed on
the workstation with native alpha32. They require the matching native
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
choice in the alpha32 flow requires a verified running instance.

The alpha33 candidate adds installed apps to this list, with search and twelve
rows per page. The existing desktop-entry model supplies names and launch
metadata; a selected closed app is verified through `cryod-app-launch --enroll`
before the Yes/No prompt. It uses the entry's working directory and does not
start the application. The native receipt still confirms the saved preference.
Definition replacement, stale policy and expired offers refuse the save.
The list follows asynchronous entry loading while the settings view is open.
Existing executable-specific app choices retain their original meaning until an
explicit replacement choice. Automatic effect activation and runtime eligibility
remain independent.

Master Off closes this client's notification and stops its request/prompt
processes. It preserves saved choices and does not undo a decision already sent;
the next refresh reads native state. Notifications use the owner's ordinary
popup timeout, with a separate offer-expiry bound. Missing helpers/failed requests
have a finite cleanup path. No periodic app observer is started by this manual
flow, and no client writes policy files, CPU quotas or cgroup freezer values.

**Suggest apps to freeze** adds a separate optional automatic flow, default Off,
under the master switch. Only the main shell owns its native subscription and
timer. CryoD measures sustained CPU use and rejects suggestions while an app is
focused or visible on any monitor. Both window-protection switches are required.
Existing Allow/Deny/Always Awake choices retain priority. Native persistent offer
history suppresses repetition across restarts; an observation or offer grants
no effect permission. The automatic-freezer setting remains independent.

Automatic requests follow the native interval and bounded catalog cursor, with
one outstanding request/prompt at a time. Decisions and their readback take
priority. Turning suggestions Off withdraws automatic requests/prompts while
preserving manual preference controls and saved choices. Master Off stops both.
`cryod.freezeSuggestions` uses the same Config writer and searchable catalog.

`tests/cryod_consent.py PACKAGE APPLICATION_TESTS` exercises the actual QML,
notify-send actions, private Quickshell notification server and native receipts.
Eight groups cover dismissal, Yes, No, Off, missing-helper recovery, a closed-app
denial, automatic sustained-CPU notification after a secondary-monitor visibility
change, and durable suppression/feature Off. The settings fixture renders an app row using a private catalog helper;
it never connects to the owner's native socket. Existing settings persistence and
the300-key catalog check pass. These checks were repeated against the alpha32
package and a candidate assembled from the actual live shell plus only the six
CryoD integration changes. The consent scope peaked at92.1MiB, the private
X/D-Bus settings scope at275.2MiB, and the catalog scope at22.5MiB; all had
zero swap and no memory-limit/OOM events.

The offline candidate additionally passes closed-app Yes/No, a never-launched
installed entry, missing enrollment helper and entry replacement while the prompt
is open. Eleven consent groups, existing QML launch routing, the actual settings
page and the 300-key catalog pass. The combined private UI scope peaked at
320.4 MiB with zero swap and no memory-limit/OOM events. This is candidate
qualification, separate from local installation and real GUI freeze acceptance.

`qs -c ii ipc call cryodConsent status` provides bounded read-only lifecycle
status. It reports whether the shell owns suggestions, has a subscription or
request/notification in flight, and whether a catalog was actually read.
Suggestion transport errors are also visible in the settings page.

Post-delivery reads confirmed the main shell owned the idle client, suggestions
remained Off, the focus bridge was fresh, and every saved configuration byte
was unchanged. The app-policy file also remained the disabled, empty baseline.
A five-second IPC timeout occurred during delayed validation; a newer shell
instance was then observed and both endpoints responded on recheck. Its cause
was not established; no manual shell/daemon restart was issued for recovery.
Subsequent kernel evidence records a root `swapoff` OOM at12:59:25 during an
owner-confirmed manual ZRAM restart, after the private test units had exited.
The relationship to the shell interruption is still unproven. ZRAM remained
active and the native owner retained its PID; this workstream did not repeat
the drain or alter the operator's command.

The catalog currently requires a verified running launcher app. Choosing an
installed app before launch, practical GUI freezer eligibility, automatic effect
activation and sustained responsiveness remain open in the native desktop goal.
No owner app was enrolled or frozen during delivery. VM Atlas publication stays
separate. Workstation receipts are under
`~/.local/state/cryod-build/alpha32-qml-20261020/`; the private desktop tracker has
`evidence/20261020-alpha32-quickshell-consent.json`.
