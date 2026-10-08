# Upstream desktop integration, 2026-10-07

Merged end-4/dots-hyprland through `33f31a08caddd41422a2d97670adeeb52b4f1e7c`
into this fork, including the 42 previously unmerged commits. The merge preserves
the fork's settings application, background/workspace fixes, audio integration,
Lua configuration, and custom package patches.

The workspace bar now uses upstream's animated occupied indicators, hover/press
feedback, app icons, and shared horizontal/vertical widgets. Right click opens
the overview; the back mouse button toggles the special workspace. Existing
workspace labels, icon preferences, compact 22-pixel buttons, and four-pixel bar
group padding are preserved. Its model stays reactive to the configured count
and each monitor's active workspace. Empty-workspace detection uses that
workspace's windows, so focusing another monitor does not erase occupancy.
Workspace numbers are painted directly to avoid an upstream shader mask
hiding inactive labels on Qt renderers. A pixel regression covers this behavior.
These controls remain under Super+I's searchable workspace settings.

Other upstream changes include Manjaro branding, single-quoted os-release fields,
workspace scroll direction corrections, suppression of application maximize
requests, and disabled blur behind the wallpaper layer. Distro parsing also now
waits for the asynchronous file load before reading its contents.

The package recipe matches the installed custom Quickshell build:
`0.3.1.r19.g5d5d498-1`, retaining the PipeWire lifetime fix, popup test fix, and
Hyprland reconnect patch. This merge does not replace it with upstream dots'
older engine pin. Fedora, Gentoo, Konsole, Fish, and dinit installation updates
are included in the source merge; distro installation workflows were not run.

Validation:

- Private two-output KWin/Hyprland test: real workspace widgets load; populated
  and empty workspaces, monitor focus, workspace groups, special workspaces,
  count changes, both orientations, and distro parsing are exercised.
- Private Settings UI: browsing, persisted controls, validation, tile editing,
  font preview/application, unrelated value preservation, and compact layout.
- 51 workspace placement assertions, 10 fullscreen assertions, four workspace
  motion tests, and settings schema/catalog validation.
- The merged Hyprland configuration passes `--verify-config`; changed shell
  scripts and the package recipe pass syntax checks.

Run the new regression without using the live desktop:

```sh
dbus-run-session -- python3 tests/quickshell_workspace_integration.py
```

The test requires Quickshell, KWin Wayland, Hyprland with Lua configuration,
Kitty, grim, and Python Pillow. It uses a disposable home, runtime directory, and D-Bus session,
then terminates only its own processes. Artifact paths are printed on completion.
