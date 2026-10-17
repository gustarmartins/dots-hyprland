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
- **Control center** offers Classic or Custom tiles, the exact grid column count,
  tile add/remove/reorder/size, sliders, corner gestures and panel retention.
- **Workspaces & dock** and **Desktop widgets** expose overview, dock, clock and
  weather settings, including placement and the digital clock's font axes.
- **Mail** connects Thunderbird accounts, local verification-code and link actions,
  and notification previews. Its master switch stops the owned mail service;
  see [Mail integration](mail.md) for setup and lifecycle details.
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

## Saved wallpapers and offline previews

The Wallpapers page opens with discovery, rotation and storage controls. Open saved wallpapers & previews switches to a separate thumbnail library of discovery and rotation downloads, search, Ready and Kept filters, and Apply/Restore buttons. Keep protects an image from automatic cleanup. Existing downloads are indexed in place in Pictures/Wallpapers/Discovery; opening Settings does not change the wallpaper or palette.

Prefetch downloads a batch without applying it or rebuilding colors. The batch defaults to six and is configurable. Rotation uses matching ready originals before contacting the API, so a prepared queue works offline. The optional Keep the offline queue filled control lets the main shell refill it while automatic rotation is enabled. Prefetch does not reset the rotation deadline.

The default collection limit is 1024 MiB with a 2048 MiB free-space reserve. Both limits are editable in Settings. Oldest unkept managed originals are pruned only when needed; current and kept wallpapers are protected. If protected originals fill the budget, new downloads pause. Manually added files and symlink targets are not deleted. Download validation precedes eviction, and an original is recorded before attempting to apply it, so failed downloads do not evict history and failed applies leave a restorable image.

## Coverage and ownership

`modules/settings/SettingsCatalog.js` classifies every leaf in `Config.qml`:
289 visible settings/readouts, two wallpaper paths owned by the picker/generator,
and four retained legacy keys without current runtime consumers. The OSK layout
is shown read-only because the compositor keyboard service owns it.

The retired controls are `bar.workspaces.showNumberDelay`,
`language.translator.engine`, `sidebar.booru.allowNsfw`, and
`sidebar.booru.defaultProvider`. Existing saved values are not deleted. Image
provider/content choices continue to be owned by the sidebar's persistent state.
Recording paths remain exposed and are consumed by the recording script.

Desktop effects, audio presets, and font profiles keep their existing helpers as
the authority. The settings app does not create a parallel set of their presets.
Design integrates the existing desktop-effects helper; About stays in navigation. Legacy effects and fonts IPC destinations open their sections inside Design.

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

## Design hierarchy

Super+I opens Design first. Color & theme leads with Light/Dark, the Material palette style and live color swatches. Accent, application theming and terminal palette controls expand underneath. Mode and palette edits use the existing switchwall/Matugen helper. Opening or expanding a section does not regenerate colors.

Desktop GPU effects keeps complete-look presets, blur and glow visible. Its detail expander groups glass, atmosphere, geometry, opacity and saved preset management. Animations keeps the profile picker visible and groups timing, springs, motion blur, workspace movement and window entrance beneath its expander. GPU presets apply immediately; individual GPU and animation edits remain a draft until Apply custom changes. Apply and Reset stay pinned in the window footer while there are pending edits; Reset edits restores the current state.

Shell surfaces, Typography and Background rendering use the same core-controls-then-details structure. Typography loads the desktop font profile tools only when opened. Search still reaches every setting directly, including controls inside collapsed sections. Narrow windows retain sidebar labels. Other desktop feature pages keep their existing organization pending user review of this Design structure.

The wallpaper library is loaded only after Open saved wallpapers & previews. Back to wallpaper controls restores the settings view. Prefetch, restore, favorites, rotation and storage limits keep their existing helper ownership.

## Memory locks, OOM alerts and Eden boost

Super+I → Memory locks delegates to the optional Linux Memory Toolkit helpers
`noswap` and `oom-notify`. Install those helpers and their user units first.
The **Locked** tab shows each live protected PID with RSS, swap, group size and
lock age, largest RSS first. Sort by RSS, swap, name or PID. Amber highlights
RSS at least 1 GiB or 5% of installed RAM, whichever is larger; this is a review
cue, not an automatic policy. RSS includes shared pages and should not be summed
as unique RAM use. The available-RAM summary uses the kernel's MemAvailable.

**Suggested** shows up to six unlocked groups in the chosen sort order, with one
representative PID per group. Consider frequently used apps; size alone is not
a reason to lock. **Search PID** filters all your processes by PID or name.
Readings refresh every ten seconds while enabled and open, with a manual Refresh.
Failed reads disable the process controls instead of reporting stale data as live.

Lock previews show the entire affected group, its RAM/swap usage and available
RAM. Shared groups, large groups or low available RAM require an explicit risk
checkbox and **Lock anyway**. That choice permits the operation; it adds no
memory veto. PID start time, UID, boot, cgroup identity, membership and the old
swap limit are checked again before applying. Changed targets require a fresh
preview. Release restores the saved limit for the group and leaves its apps
running. Protection configured outside noswap is labelled without offering to
release someone else's limit. Administrator-owned groups link the workflow back
to the terminal, where the helper can authenticate.

The explanation describes swap delays, group scope, existing swap, reclaimable
file pages and the tradeoff when RAM runs out. These are swap bans, not mlock
or a guarantee against slowdowns. **Automation and reminders** keeps independent
name-following and age-reminder switches. Master off releases locks and stops
the helper's timer while retaining names/preferences. Failed restores stay
visible for review. Browsing never starts the timer or changes locks.

OOM alerts have their own master switch, source switches, labelled test and
recent history. Off stops each integration's owned background work and hides
its optional feature controls. Search settings for “noswap”, “RSS”, “PID”,
“process search”, “OOM”, or “memory kills” to find these destinations.

The process browser requires `noswap dashboard` schema 2 and `noswap inspect`
from Linux Memory Toolkit. Verify the UI without changing real locks with
`xvfb-run -a -s '-screen 0 1400x1000x24' dbus-run-session -- python tests/memory_locks_ui.py`.

Super+I → Audio contains the Eden boost master/reset controls; search “Eden” or
“Mario Kart”. The sidebar widget uses double-click for +12 dB and single-click
for reset. See [audio presets and Eden boost](audio-presets-and-eden-boost.md).
