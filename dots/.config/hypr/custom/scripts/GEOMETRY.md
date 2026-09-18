# Window geometry and float controls

- Super+F10: toggle restoring saved geometry for **new** windows.
- Super+Ctrl+F11: save/remove the focused app's geometry.
- Super+Ctrl+F12: save/remove an exact class + title geometry rule.
- Super+F11: toggle master float. Enabling floats the active workspace's eligible windows and centers new windows at up to 1200×800. Disabling tiles only windows this feature floated, across their current workspaces. Pre-existing floats and geometry-restored windows remain floating.
- Super+F12 / Super+Shift+F12: toggle the focused app/title's exemption from master float's forced size.

Saved geometry takes precedence over master float. Coordinates are relative to the window's actual monitor; restoration clamps sizes/positions to its logical usable area, including scaling, rotation, and reserved edges. Fullscreen, pinned, and hidden clients are skipped. Existing animation properties and z-order are preserved.

`autofloat_positions.json` retains the old class / `class::title` format. Saves and exemption changes apply to subsequent opens immediately. A missing file means no saved rules. Archived `.old` files are never implicitly imported. Invalid data is reported without rewriting it. Save/remove remains a toggle, as before.

The shell shortcuts delegate to `window-geometry.py`; there is one listener per Hyprland instance. Geometry's enabled marker persists, while master float and its ownership records belong to the compositor session. Lua config startup/reload ensures a listener only when a feature is enabled. Runtime control uses a Unix socket and locks, not PID-based process killing. The listener exits when the compositor disconnects.

```
python3 ~/.config/hypr/custom/scripts/window-geometry.py status
~/.config/hypr/custom/scripts/geo-daemon.sh --ensure
~/.config/hypr/custom/scripts/geo-daemon.sh --stop
python3 -m unittest discover -s ~/.config/hypr/custom/scripts/tests -v
```

Logs: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/geometry/daemon.log`.
The first three seconds after opening allow late app/title resolution. Later title changes never move a window that you have already positioned for work.

These controls govern floating geometry; they do not rebalance Dwindle's tiling tree. Existing organization controls include Super+Tab (overview, including drag between workspaces), Super+D (maximize), Super+Alt+Space (float/tile), and Super+Alt+1…0 (send to workspace). There is currently no whole-workspace balance shortcut. Native Dwindle `movetoroot` promotes one window; scrolling layout is another available option for many readable windows without recursively shrinking tiles.
