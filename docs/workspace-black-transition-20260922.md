# Black transitions when selecting new workspaces

The fullscreen helper treated incomplete native workspace discovery anywhere as
fullscreen on every monitor. Clicking a previously unvisited workspace creates
a native workspace object before its JSON snapshot arrives. That brief readiness
gap incorrectly hid the wallpaper, bar and other fullscreen-sensitive surfaces,
including surfaces on the other monitor.

The helper now determines fullscreen state from the requested monitor and its
active workspace. An unrelated placeholder workspace no longer hides the screen.
Unknown monitor names retain the conservative fallback. Actual workspace/client
fullscreen flags continue to hide the appropriate surfaces.

Validation used the production bar buttons and background components in a private
two-output Hyprland session with the current slide profile. The same sequence of
14 clicks, including workspace 2 to 11–15 and a cross-monitor workspace 10, recorded
63 states with at least one incorrectly hidden background before the fix and zero
afterward. These are visibility-state observations, not rendered frame counts.
Actual fullscreen entry still hid its background and exit restored it.

Repeating with workspace JSON replies delayed by 150 ms reproduced the same
visibility failure before the fix and no failure afterward. Frame captures did
not reproduce a black image in the nested compositor; these checks establish the
visibility race and its correction, not physical-monitor visual acceptance.

Run `node tests/hyprland_fullscreen_state.cjs` for 10 focused assertions using the
production fullscreen function: partial discovery, a new active workspace without
JSON, monitor isolation, client fullscreen and unknown-monitor behavior.

No workspace dispatch, animation timing, widget positioning or effects preference
changed. Quickshell's [workspace documentation](https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/HyprlandWorkspace/)
distinguishes the native properties from the separately refreshed JSON snapshot.
