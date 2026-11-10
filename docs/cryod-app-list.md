# CryoD app list

The app freezing list defaults to **Seen or configured**, ranked by measured
background CPU and observed activity. Launcher entries without observations or a
saved freezing preference are available through **All installed apps**. Filters
also cover seen apps, background CPU and currently registered apps; sort by CPU,
last seen or name, with optional 1/5/10/25% minimum CPU thresholds.

Rows distinguish the catalog's running-at-refresh observation, last seen time,
peak sustained background CPU and missing measurements. 100% is one CPU core.
Saved choices are not evidence of app use. A missing CPU value is never zero.

The existing main-shell suggestion client retains native `recommend` replies,
including numeric `cpu_percent_x100` values even when `recommended` is false.
No additional polling, native effects, permissions or subscription is introduced.
The settings process only reads the shared history. CPU observations are limited
to apps and windows the existing suggestion observer measures: this is not a
complete process CPU profiler or a reconstruction of past use. Previously
discarded CPU figures cannot be recovered. History continues with suggestions
On; existing app choices and integration switches are unchanged.

History lives at the Quickshell state location in
`cryod-app-observations.json`, version 1. It contains app IDs and observation/peak
timestamps and values, not process identities or permission decisions. Retention
is bounded to 256 apps/30 days, writes are coalesced to at most once per minute,
and malformed files are preserved with a UI error. Master Off prevents collection
and writes. Settings refresh still uses the native catalog for current choices
and process identity; historical rows cannot authorize an action.

Verification (2026-11-10): `node tests/cryod_app_stats.js`,
`dbus-run-session -- python tests/cryod_app_history.py`, and both
`tests/cryod_settings_ui.py` and `tests/cryod_app_stats_ui.py` under private Xvfb/
D-Bus passed. They cover sort/filter thresholds and unknowns, retention, real QML
persistence/reload/restart, single-writer behavior, corruption, master Off,
rendered controls, empty states and preservation of unrelated settings. The
native consent test copies the new JS dependency into its private fixture; no
native code or action contract changes in this increment.

Owner request: “Hey, can you make this screen of app list smarter by allowing
sort filters based on relevant usage statistics of apps I already used and were
seen by CryoD using X cpu In background so it is more helpful than just showing
everything alphabetically. there are stuff there I havent ever used in my life”

Terminal scope: the catalog is registered desktop applications, not individual
shell commands or tmux sessions. Terminal-mode desktop entries are excluded by
the existing installed-entry list. Codex inside Kitty/tmux is not automatically
attributed as a separate app; a registered terminal group is not proof of which
job consumed CPU. Session/group attribution remains separate work.

Live delivery: three matching files applied on November 10. The main shell
reloaded successfully: consent remained enabled/subscribed with no reported
error, and the new observation endpoint reported ready. Initial retained app/CPU
counts were zero; live CPU accumulation is not claimed by the isolated fixtures.
Settings were not opened or focused. The complete config hash stayed unchanged.
Rollback copies and SHA-256 receipt:
`~/.local/state/cryod-app-list/20261110T124747Z/receipt.json`.
