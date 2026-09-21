# Quickshell audit follow-up — September 20, 2026

The current engine remains pinned to `c6a516096dd84d5255b409482eb4bf740b952f88`, with the existing PipeWire QPointer fix. This change updates the custom shell for that engine.

## Changes

- Notification dismissal and sender withdrawal now release wrappers and timers. Group removal updates membership once; history writes coalesce over 100 ms and flush from ShellRoot during reload/shutdown. Unreadable history remains intact while new notifications still work in memory.
- Saved notification images discard process-local `image://qsimage/` handles and retain durable references. Failed images fall back to the app icon. Restored history has no stale native actions.
- Hyprland clients, monitors, workspaces and active workspace use the native models. Only layer discovery still launches `hyprctl`; the 250 ms title throttle remains. Native initialization owns the first monitor fetch to avoid racing creation.
- Notification cards use the shared glass opacity rules and rounded native blur/input regions, including animated movement and viewport clipping.
- A shared workspace model adds named special workspaces and one MultiEffect icon layer. The existing 20-slot sizing, bar fitting and back-button action remain.
- Toolbar targets tolerate missing delegates and keep their indicator aligned within a wider container. Popup placement waits for its anchor window. Translator and AI command delegates tolerate teardown.
- Completed wallpaper-discovery and EasyEffects preset-picker changes are synchronized from the deployed desktop. The EasyEffects helper and tray-aware startup command are included; no presets or private user configuration are bundled.

## Validation

- 23 notification integration checks using the actual QML service, a private D-Bus and temporary history: lifecycle, actions, burst/bulk persistence, immediate reload/shutdown, corrupt-history handling and restart.
- 10 isolated widget assertions: card regions, opacity controls, fallback images, drag/expand geometry and 20-slot sizing; both desktop families compile.
- 10 native integration checks in virtual KWin plus nested Hyprland: two outputs, four notification cards, shaped regions, movement, fullscreen entry/reload/exit, named special workspace and output removal.
- Wayland capture: all 252 observed notification blur-region updates matched their input regions; the union excluded card gaps and rounded corners.
- Images inspected for the left-sidebar surface, bar popup and notification cards. Blur-on/off pixel differences were confined to surfaces; sampled outside space, card gaps and rounded cutouts were unchanged.
- Live deployment retained all 39 history records and cleared three stale image handles. Final reload produced no warnings; focus, player state, EasyEffects preset and shell settings were unchanged. The existing shell process and respawn owner were retained.

Run the notification suite with Quickshell, Python `dbus` and `gi` installed:

```sh
dbus-run-session -- python3 tests/quickshell_notification_integration.py
```

It uses the production service through a relative fixture symlink, does not contact the desktop notification server, and writes its results to a temporary directory.

## Deliberate optional decisions and limits

Native Networking migration is deferred: the existing `nmcli` implementation works, and replacing password/reconnection/Ethernet behavior needs separate acceptance. No physical network connection was changed. `DropExpensiveFonts` remains off: active families resolve to TTF/OTF and no benefit has been measured; filtering WOFF font fallbacks would be an unvalidated change.

The earlier generic shader-source warning did not recur in isolated rendering or the final live reload; its original component was not conclusively identified. Virtual fullscreen/hotplug checks do not claim physical monitor hotplug or Eden gameplay acceptance. No CPU/frame-time improvement is claimed. Native Polkit, disabled idle policy, Qt text rendering, bar fit and fullscreen one-shot screencopy remain in place.
