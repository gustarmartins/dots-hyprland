# Display recovery

`refresh-displays` uses `~/.config/hypr/monitors.lua`, also loaded at login.
It requires Bash, Hyprland with Lua IPC, Lua, jq, Python 3, flock, timeout, and
the installed `vrrctl` helper, and `hyprsunsetctl` when color IPC is available.

The AOC uses its saved per-display VRR policy; `-1` selects the global default.
The larger QS VRR panel selects a display or the global default, then Off (`0`),
Always (`1`), Fullscreen (`2`), or fullscreen games/video (`3`). Displays may
follow the global default (`-1`). The default is fullscreen-only; ARZOPA stays
Off unless explicitly changed. Settings use `vrrctl`, `~/.config/hypr/vrr.json`,
and its generated `vrr-policies.lua`. `custom/vrr.lua` loads after shell overrides,
so older toggle values cannot shadow this policy. Sunshine's canonical restore
profiles use the same saved per-display policy.

The controller preserves the live resolution, refresh rate, position, color, and
brightness. Hyprland 0.57 ignores VRR in its monitor-rule comparison; the helper
forces a soft-rule update with a temporary 0.00001 brightness difference and
restores the exact brightness before completion. It does not power-cycle outputs.
The panel reports compositor and kernel DRM `VRR_ENABLED` state; kernel VRR
enabled is not a measurement of variable refresh cadence or physical flicker.
State refresh runs only while a panel is visible. Removing/hiding the widget
stops its polling; selecting Off disables VRR for the selected display.

Use `vrrctl status` for readback, `vrrctl set DP-1 2` for a display, or
`vrrctl set global 2` for the default. A display disconnect or conflicting display
transaction is reported without applying a change to another output.

Profile restoration reuses `vrrctl`'s soft-rule workaround under the existing
refresh lock, including for a selected-output wake/cycle. It changes no saved
VRR settings and restores the exact brightness after the temporary nudge. `verify` also
checks the saved global VRR policy and resolves Follow global when checking
Always/Off. Fullscreen policies report current activation separately because
activation depends on the displayed content. This verifies configuration, not
animation frame rate or perceived smoothness.

| Command | Behavior |
| --- | --- |
| `refresh-displays cycle DP-1` | Holds DP-1's video signal off for at least five seconds, wakes it, and reapplies only its saved profile. |
| `refresh-displays` | Cycles each currently awake display in sequence. Already sleeping outputs remain asleep. |
| `refresh-displays sleep` | Puts connected displays in standby, with a one-second lead-in and five-second protected off interval. |
| `refresh-displays wake` | Wakes connected displays and reapplies their profiles. Safe to repeat. |
| `refresh-displays apply` | Reapplies profiles without explicitly blanking displays. |
| `refresh-displays status` | Reads current output and color settings. |
| `refresh-displays verify` | Checks connected outputs against the saved profiles. |

`sleep` and `wake` also accept an output name, such as `DP-1`. Keep monitor
power and cables connected for ordinary standby. After the initial protected
interval, the previous keyboard/mouse wake settings take effect again. With
both enabled, pressing a key or moving the mouse wakes the displays; running
`wake` afterward is optional. These commands do not suspend or resume the PC.
If a monitor is physically switched off, switch it on first. Software cannot
wake an unplugged monitor.

Cycle temporarily suppresses input-triggered wake so releasing Enter or moving
the mouse cannot collapse the off interval. Sleep uses the same protection
while entering standby. The helper restores the previous input wake settings
on completion, error, SIGINT, or SIGTERM. It installs no background service and
does not edit the persistent input settings. Normal process cleanup cannot run
after SIGKILL; if forcibly killed, explicitly wake the displays and reload the
Hyprland settings to restore the configured input wake policy.

The command checks Hyprland's DPMS state and connected DRM sysfs connector
state, including repeated checks during the off interval. Early wake, failed
off commits, and disconnects produce an error instead of a success message.
The real refresh lock protects mutations; status and verify remain usable
during a cycle. Outputs/workspaces are not removed from the layout.

This is a DPMS/video-signal reset, not a power cut to the panel electronics.
The software checks cannot establish physical panel standby, a full hardware
reset, or perceived font sharpness. A monitor may show its no-signal message
before its firmware enters standby.

For a controlled longer standby, use
`refresh-displays cycle DP-1 --off-seconds 15`. The explicit option accepts
5–60 seconds and also works with `sleep`; the default remains five seconds.
Input wake is suppressed for the entire requested interval. This avoids
combining multiple resets and font changes when comparing a sharpness problem.
A longer interval is a diagnostic option, not a proven sharpness fix: identical
mode, scanout and DDC readbacks do not establish identical physical output.
Capture the bad state before resetting and compare the same content afterward.

The owner-approved DP-1 rendering on 2026-10-22 matches the existing profile:
1920x1080 at 144 Hz, position 0x0, scale 1, transform 0, 8 bpc/XRGB8888, sRGB,
and VRR enabled. No profile, font, or color-setting change was needed for this
repair. The local reference capture is under
`~/.local/state/refresh-displays/reference-20261022-161136/` and includes
Hyprland/DRM readback, EDIDs, fontconfig, color state, profiles, and the previous
command. Physical panel appearance remains the owner's acceptance check.

Run isolated regression tests with `python3 tests/test_refresh_displays.py`.
They use a disposable home, fake IPC/sysfs, simulated input, and virtual time;
they never connect to the real compositor or blank a display.

## Sunshine streaming layouts

Sunshine is opt-in on this workstation. Its user service is disabled at login
and has no automatic restart. Run `sunshine-session` (or `sunshine-session start`)
when you want to connect from Moonlight. Use `sunshine-session stop` to stop it
manually, and `sunshine-session status` for its current state. Starting it does
not enable autostart. The existing paired clients and app entries are retained.

While started, the service supervisor blocks on Sunshine's output and process
exit events; it does not poll the compositor, phone, network or logs on disk.
It stops Sunshine after the last client disconnects, or after Sunshine reports
a network timeout (normally up to ten seconds after a lost connection).
Returning to Moonlight later requires starting Sunshine again. INFO logging is
selected for this run instead of per-input debug logging, without rewriting
`sunshine.conf`. Tray quit, a crash or a manual stop also runs display cleanup.
The supervisor and its recovery record identify the exact Sunshine child by
PID, process start time and executable; detached games are not killed with it.

`sunshine-display prepare {aoc|arzopa|virtual|auto} [60|120|auto]` temporarily
selects a streaming layout. Before making changes it records the current
Hyprland instance in `$XDG_RUNTIME_DIR/sunshine-display.pending`, under the
existing display-helper lock. `sunshine-display restore` restores the canonical
monitor profiles only when that session has pending changes. A successful
restore clears the marker; failed restores retain it for retry. Markers from an
earlier compositor session are discarded without changing the current layout.

Both the Sunshine app undo command and its systemd `ExecStopPost` hook can call
`restore`: the second call does nothing. Quitting an idle Sunshine instance also
does nothing to the displays. This prevents unnecessary profile, VRR and color
reapplication at every tray exit. `sunshine-display restore --force` retains
explicit manual recovery when no marker exists.

The helper selects a unique live compositor rather than trusting an old socket
directory. It respects the shared display lock, checks Lua IPC error text and
restores the desktop if preparation fails. Waking a sleeping output only changes
DPMS, preserving the selected streaming refresh rate. Recovery keeps the virtual
output and pending marker if no physical output can be restored, allowing a
later retry instead of leaving the compositor with no usable output.

Run `python3 tests/test_sunshine_display.py` for isolated ownership, duplicate
cleanup, failure/retry, session-boundary and lock tests. They use fake compositor
and recovery commands and never change physical displays. Run
`python3 tests/test_sunshine_session.py` for real private-process tests of the
on-demand supervisor, including orphan recovery and detached-app lifetime.
