# Floating windows drift off-screen after monitor reconnection

On Hyprland 0.56.2 (`efb50993780079460b0cbed1363e2166a2de1d9f`),
floating windows can remain mapped to the correct workspace while their global
coordinates drift farther off-screen on each monitor power/reconnect cycle.
The workspace bar continues to count these windows correctly.

The isolated reproduction uses a second output at `(1920, 500)`, a floating
terminal at `(2080, 620)` with size `700 x 450`, and another active workspace.
Removing that output moves the terminal to `(160, 120)` on the first monitor.
Recreating it incorrectly leaves the terminal at `(159, 119)`. After three
cycles it reaches `(-3683, -883)`. The terminal process and workspace survive.

## Owning-layer cause

In the exact running source, `CMonitor::onConnect` calls `setupDefaultWS` and
returns workspaces before deferred monitor arrangement has assigned the new
output's position. `CWorkspacePlacementController::moveWorkspaceToMonitor`
translates floats from the old origin to the new monitor's temporary `(-1,-1)`
origin. Later `CMonitor::moveTo` initializes the real origin but deliberately
returns early when the old position was `(-1,-1)`, omitting the corresponding
window translation. The offset therefore accumulates on each round trip.

Source paths at that commit:

- `src/output/Monitor.cpp`: `onConnect`, `setupDefaultWS`, `moveTo`
- `src/state/WorkspacePlacementController.cpp`: `moveWorkspaceToMonitor`

The display refresh helper uses DPMS, not output removal. Hardware can still
report a disconnect when powered off. This reproduction proves the compositor
reconnect defect; it does not establish which physical power operation triggered
a particular historical occurrence.

## Session-compatible correction

`custom/float-hotplug.lua`, loaded from `custom/general.lua`, records eligible
floating windows only when `workspace.move_to_monitor` targets an unarranged
monitor at `(-1,-1)`. After `monitor.layout_changed`, it supplies the missing
origin translation. A single deferred pass covers alternate event ordering.
There is no recurring timer or blanket bounds enforcement.

PID, workspace, monitor, position and size must still match the captured state.
User moves/resizes, native corrections, closed windows, tiled windows, pinned
windows, hidden clients, fullscreen clients and special workspaces are excluded.
It preserves window size, focus and workspace ownership. Old, already displaced
windows need a separate one-time recovery; this module prevents future drift.

The correction is intentionally narrow. If a later compositor fixes the native
translation, its updated coordinates cause this module to skip the window.
Remove the require from `custom/general.lua` and reload to disable it.

## Verification

```bash
lua dots/.config/hypr/custom/scripts/tests/test_float_hotplug.lua
dbus-run-session -- python3 tests/hyprland_float_hotplug.py
# Optional: demonstrate native drift on an affected compositor, without the fix.
dbus-run-session -- python3 tests/hyprland_float_hotplug.py --baseline
```

The integration test launches virtual KWin, a nested Hyprland and a disposable
Kitty; it never sends commands to the live desktop. Three output destruction /
recreation cycles retained the exact `(2080,620)` position and `700 x 450` size
with the correction. Unit checks cover idempotence, identity, state changes and
eligibility exclusions. The four affected live terminals were separately brought
back into their existing workspace, with processes and sizes retained; the user
confirmed they were visible. Physical power-button recurrence remains a separate
acceptance check from the nested-compositor reproduction.
