# Desktop settings

Open Settings with the existing Super+I shortcut. The app now follows the current
fork instead of putting most controls into one long Interface page.

- **Your desktop** gives a starting point for each area.
- **Desktop effects** retains its draft, Apply, saved looks, and animation flow.
- **Wallpaper & colors** includes discovery, rotation, palette generation,
  transparency, wallpaper motion, and terminal-color tuning.
- **Text & fonts** lists all 26 fontctl profiles, with compact and grayscale
  options, preview, and explicit desktop apply. Individual shell roles and point
  sizes remain available below it.
- **Bar & resources** includes monitor selection, workspace indicators, tray,
  warnings, sampling interval and history length.
- **Control center** offers Classic or Custom tiles, the adaptive column limit,
  tile add/remove/reorder/size, sliders, corner gestures and panel retention.
- **Workspaces & dock** and **Desktop widgets** expose overview, dock, clock and
  weather settings, including placement and the digital clock's font axes.
- **Notifications**, **Capture & overlays**, **Launcher & apps**, **Audio & night
  light**, **Time & language**, **Lock & power**, **Sidebar services**, and
  **Advanced** keep their controls in focused, searchable groups.

Ctrl+F searches names, descriptions and config keys across every page. Search
also links to the separate effects, wallpaper, font and audio editors. Ctrl+Page
Up/Down changes pages. The navigation rail and editor layout adapt to narrower
windows. The original window title stays intact for the existing Hyprland float
rule.

Switches, choices and step buttons save on user actions. Single-line text and
numbers save when editing finishes; lists and long text have an explicit Save
button. Opening pages or receiving an external config update never submits a
control's initial value. Invalid numbers, times, accent colors and model arrays
show an error without overwriting the saved value. Changes to unrelated values
are preserved, including extension keys not declared in Config.qml. The shared
writer merges known properties into the loaded JSON instead of dropping unknown
keys through JsonAdapter serialization. ConfigKeys.js is checked against the
schema by the same coverage test.

Font apply uses `fontctl --user-only`: it updates user-level fonts and restarts a
running shell. A successful preview is required first. The settings writer pauses
while the tool works, then reloads the updated file before allowing more edits.
System Fontconfig elevation remains available through fontctl in a terminal.
The active font is not changed just by opening this page.

Quick-tile editing changes layout only; it never executes the tile's memory,
network, audio or other action. EasyEffects presets require an explicit Apply.
Wallpaper discovery and external commands also require a button press. Previously
enabled automatic wallpaper rotation continues to be owned by the main shell.

## Coverage and ownership

`modules/settings/SettingsCatalog.js` classifies every leaf in `Config.qml`:
285 visible settings/readouts, two wallpaper paths owned by the picker/generator,
and four retained legacy keys without current runtime consumers. The OSK layout
is shown read-only because the compositor keyboard service owns it.

The retired controls are `bar.workspaces.showNumberDelay`,
`language.translator.engine`, `sidebar.booru.allowNsfw`, and
`sidebar.booru.defaultProvider`. Existing saved values are not deleted. Image
provider/content choices continue to be owned by the sidebar's persistent state.
Recording paths remain exposed and are consumed by the recording script.

Desktop effects, audio presets, and font profiles keep their existing helpers as
the authority. The settings app does not create a parallel set of their presets.
The seven superseded settings pages are removed; About and Desktop effects are
retained and integrated into the new navigation.

When changing Config.qml, update the catalog with a supported control, a managed
owner, or an explicit retirement reason. `tests/settings_catalog.py` checks full
coverage, duplicate keys, numeric defaults, enum values, dependencies, the real
quick-tile type list and the fontctl catalog. This prevents new fork options from
silently being omitted again.

## Validation

```bash
python tests/settings_catalog.py
xvfb-run -a -s '-screen 0 1400x950x24' dbus-run-session -- python tests/settings_ui.py
bash -n dots/.local/bin/fontctl
shellcheck -S error dots/.local/bin/fontctl
```

The UI test uses a disposable home, private X server and D-Bus session. It opens
all 17 pages and checks unchanged configuration while browsing, real mouse/key
edits, persisted values, invalid input rejection, tile addition, narrow-window
rendering and font preview. Font apply uses a test helper to verify the writer
pause/reload sequence without changing the real desktop. Optional host services
are stubbed; physical appearance and actual font/audio changes are separate from
these automated checks.
