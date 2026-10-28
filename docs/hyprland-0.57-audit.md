# Hyprland 0.57 package compatibility review

Reviewed Arch `hyprland 0.57.0-1` against the installed compositor commit
`0aa6745f705f2c4b0a5004eb019ef76e5bbdb426`, comparing its configuration,
dispatchers, input handling, Lua object properties, and workspace IPC with 0.56.2.
The Arch recipe changes build configuration, not these runtime interfaces.

Source references:

- [Arch package recipe](https://gitlab.archlinux.org/archlinux/packaging/packages/hyprland/-/blob/0.57.0-1/PKGBUILD)
- [Keyboard event arguments and ordering](https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/config/lua/LuaEventHandler.cpp)
- [Keybind matching and release callbacks](https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/keybinds/Manager.cpp)
- [Lua workspace identity](https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/config/lua/objects/LuaWorkspace.cpp)
- [Workspace and monitor JSON](https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/ipc/s1/Commands.cpp)

## Changes

Super tap detection now belongs to the compositor. The previous Lua bindings
sent `searchToggleRelease` to Quickshell but omitted the legacy interruption
bindings; Quickshell receives a release even after a Super shortcut. The new
helper arms only when Super is the sole pressed key, cancels on additional keys,
modifiers, mouse buttons or scrolling, and sends `searchToggle` only after a
clean release. It preserves shortcuts and the workspace-number overlay, does not
switch submaps, and keeps mouse observers transparent and non-consuming. The
fallback launcher now follows the same tap decision.

Named and special workspaces no longer have numeric Lua IDs. Their JSON objects
use an address and may omit `id` too. The review found several affected paths:

- The close-window guard compares native workspace objects instead of allowing
  two absent IDs to match a hidden window.
- Monitor-reconnect correction explicitly limits itself to numbered workspaces
  and excludes nil IDs without raising a Lua comparison error.
- Sending to the scratchpad recognizes its addressable name.
- Shared JSON identity helpers match nonempty workspace addresses, retain
  compatibility with older numbered/negative IDs, and reject missing identities.
  The scratchpad indicator, screenshot target visibility and CryoD visibility
  feed use these helpers. Monitor snapshots retain the workspace address, and
  workspace readiness accepts snapshots without numeric IDs.
- Lock/unlock saves addressable selectors and sends a single quoted Lua IPC
  command. The old shell batch contained an obsolete `keyword animation`
  command; removing it preserves the configured animation policy.

The public shadow default was also stale: `render_power = 10` fails current
configuration validation. It is now `4`, matching the already-corrected live
base configuration. User overrides remain separate.

The active Lua configuration reports no deprecated settings. The existing Lua
dispatcher expressions remain supported by the current `dispatch` IPC wrapper.
Unused legacy `.conf` examples are not treated as active configuration. The
workspace bar remains a numbered-workspace grid; these fixes do not introduce
a new UI for arbitrary named workspaces or replace the pinned Quickshell engine.

## Validation

- Real isolated Hyprland input: both Super keys, clean taps, bound/unbound keys,
  modifiers, both release orders, a previously held key, both Super keys held,
  and recovery to the next clean tap. Mouse bindings are checked for
  non-consuming registration; physical mouse gestures are not claimed tested.
- Real two-monitor KWin/Hyprland/Quickshell integration: occupancy and focus,
  empty workspaces, groups, scratchpad open/close, live count changes, both bar
  orientations, pixel-visible labels and completed shell reload.
- Production Lua close guard and reconnect exclusions; 20 JSON workspace
  identity assertions; lock/unlock command generation, Lua parsing and selector
  quoting without invoking the real lock screen; existing fullscreen checks.
- Python unit suite: 154 tests passed under system Python; the five terminal
  colour tests passed using the existing Quickshell Python environment, which
  supplies `materialyoucolor`.
- Isolated Settings UI, schema/catalog, widget creation/teardown, clock reload,
  spatial/storage controls and native CryoD session bridge/Off acknowledgement.
- Live and repository Hyprland configuration validation; live config errors and
  deprecated-settings lists are empty. Scoped fixes were applied without
  restarting the compositor or Quickshell process.

The tests use private displays, homes and IPC sessions. No physical hotplug,
live lock/unlock, gameplay smoothness or owner keyboard acceptance is inferred.
