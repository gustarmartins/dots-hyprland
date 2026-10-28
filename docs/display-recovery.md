# Display recovery

`refresh-displays` uses `~/.config/hypr/monitors.lua`, also loaded at login.
It requires Bash, Hyprland with Lua IPC, Lua, jq, Python 3, flock, timeout, and
the existing `hyprsunsetctl` helper when color IPC is available.

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
