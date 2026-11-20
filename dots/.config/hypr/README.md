# Hyprland settings map

Start here instead of editing the similarly named legacy files.

| Setting | Active file or control |
| --- | --- |
| Screen resolution, Hz, position | `monitors.lua` |
| VRR / FreeSync per monitor | Control center's VRR panel, or Super+I → Control center |
| Your keyboard, mouse, general preferences | `custom/general.lua` |
| Your keyboard shortcuts | `custom/keybinds.lua` |
| Per-window rules | `custom/rules.lua` |
| Workspace-to-screen mapping | `workspaces.lua` |
| Blur, glow, animation, saved looks | Super+I → Design → Desktop effects |
| Lock screen, idle, portal | `hyprlock.conf`, `hypridle.conf`, `xdph.conf` |

`hyprland.lua` is the entry point. It loads the base `hyprland/` modules, your
`custom/` modules, workspaces and monitors, then the shell's overrides. The final
`custom/vrr.lua` module owns VRR so that it has one settings path.

The shell manages `hyprland/shellOverrides/main.lua`. Desktop effects generate
`custom/cinematic-effects.lua`. The VRR panel writes `vrr.json` and generates
`vrr-policies.lua`; use the panel or `vrrctl` rather than editing generated files.
The base `hyprland/` folder supplies defaults; put personal edits in `custom/`.

To switch both current screens back to 144 Hz, change the shared mode in
`monitors.lua` to `mode = "1920x1080@144.0",`, save, then run `hyprctl reload`.
Use `1920x1080@60.0` for the current 60 Hz experiment. Hz and VRR mode are separate.

`.conf-old/` contains former Hyprland `.conf` files, preserving their relative
paths. They are not loaded. The active lock/idle/portal configs remain outside
that folder. Files ending in `~` are editor backups, not configuration inputs.
