# EasyEffects widget and audio state repair — 2026-10-07

The live configuration and dots repository contain the same scoped widget,
service and helper changes. Quickshell revision `41651d7` is installed and its
running executable hash was verified after the host reboot.

## Widget behavior

- The equalizer icon is a separate processing button. The description and tile
  body open EasyEffects. Right click also opens the app. Both compact and expanded
  sizes use this interaction; tile editing retains its existing behavior.
- The tile shows **On/Off**, the preset in expanded mode, and separate icon hover
  feedback. Busy actions show Updating and disable interaction until completion.
- Processing state uses confirmed global bypass and service availability. A
  running background app can have processing turned off.
- The helper decides toggles against current EasyEffects state under its action
  lock. It returns confirmed state immediately. Delayed reads from before an
  action cannot overwrite its result.
- Unresponsive or invalid status is explicit, retains the last preset, and retries.
  It does not launch another EasyEffects instance. PipeWire device/default changes
  trigger a debounced status refresh, including while the panel is closed.

## Reconnection and audio controls

Missing sinks or microphones are unavailable and inactive. Audio controls guard
missing or unready audio objects. Volume protection resets its comparison baseline
when the output changes, preserving the replacement device's own volume.

On this workstation, the native EasyEffects setting
`EffectsPipelines/resetBypassOnDeviceChange` is now `false`. The owning app exposes
it in Preferences → Audio as **Reset Global Bypass on device change**. Its default
is true and can enable processing on an output change. Source:
[EasyEffects 8.3.0 configuration](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/contents/kcfg/easyeffects_db.kcfg).

The change required one graceful EasyEffects background restart before the host
reboot. All 876 captured output plugin values, the current preset and bypass state
matched afterward; no parameter restoration was needed. The complete database and
live values were backed up. PipeWire/Pulse/WirePlumber were not restarted by this
operation. Reopening the app after the reboot showed the full processing chain
and active links from both playback streams to the analog output.

## Upstream review and engine

Reviewed Quickshell upstream through `11ca60b` and end-4 dots through `33f31a08`.
The relevant newer fixes were installed using the same `41651d7` pin selected by
end-4's October 3 package recipe:

- [PipeWire route volume writes without a reported volume step](https://github.com/quickshell-mirror/quickshell/commit/25da30db02d7).
- [Engine destruction after root children, fixing asynchronous Loader teardown](https://github.com/quickshell-mirror/quickshell/commit/4594680eb4ba89a69f6a830174028b6e3d14ccfa).
- [Socket connection attempts after an initial connection failure](https://github.com/quickshell-mirror/quickshell/commit/41651d7dcd62a9400eb6f4f8a8580efe00901efb).
- Hyprland workspace address support.

The three existing local patches were retained and reverse-checked: PipeWire
cached-interface lifetime, popup test polish, and Hyprland event reconnection.
The fork package is `0.3.1.r18.g41651d7-1`. Later upstream changes cover Qt 6.12,
network security selection and contribution documentation. They add no further
PipeWire fix in the inspected range. Upstream dots has no newer EasyEffects state
repair to import; its process-based toggle does not cover bypass state.

## Validation

- Nine native CTest suites and the packaged Hyprland socket reconnect fixture pass.
- `tests/easyeffects_integration.py`: 27 checks pass against the new binary, using
  the actual helper, service and tile components with private EasyEffects sockets,
  a private PipeWire server, X11 and D-Bus. Coverage includes icon/body/right clicks
  at both sizes, stale external state, late responses, invalid replies, absent
  device labels, repeated sink/source removal, replacement volume preservation,
  PipeWire server restart and status refresh with the panel closed.
- Private native PipeWire lifecycle stress passes 20 cycles / 240 transitions.
- The real control-center integration passes edit/resize/drag, compact/narrow
  layout, preset picker and restart persistence. Only its fixture callbacks run.
- Installed and running Quickshell hashes match the packaged executable after
  reboot. Live EasyEffects/helper/Quickshell state agrees, selected preset is
  `codex-stinger-kick-focus`, and analog output remains 100 percent, unmuted.

Physical P2 unplug/replug and the user's live mouse acceptance remain unverified.
No live desktop input or foreground panel opening was injected. Existing unrelated
BlueZ, PowerProfiles, overview and other widget warnings remain outside this fix.

## Login startup repair — 2026-10-10

Both Hyprland startup configurations already invoke `easyeffects-qs start`.
The helper previously aborted when the StatusNotifier host did not appear within
its tray wait, or when a bus query timed out. That left audio processing stopped
for the rest of the login even if Quickshell subsequently recovered.

The helper now prefers a ready tray for up to 15 seconds of elapsed time, tolerates
bus-query timeouts, and then starts EasyEffects in background service mode even
without a tray. It records that fallback in `~/.local/state/easyeffects-qs.log`.
The Quickshell tile still controls the socket; a missing native tray icon does
not prevent processing. The existing action lock and responsive-instance check
remain in place, including refusal to duplicate an unresponsive instance.

Six isolated startup regression checks and all 27 existing integration checks
pass. The deployed helper's `start` command preserved the current EasyEffects
PID and playback. A future cold login has not yet been observed.

A further real-app test used an isolated session bus and PipeWire server with
no tray or audio hardware. The installed helper started EasyEffects with
processing enabled after 15.64 seconds; a repeated start kept the same private
PID. The live desktop instance stayed untouched. This exercises the actual
fallback launch, beyond the mocked startup tests; it is still not a cold-login
observation.

## Evidence and recovery

Durable receipts, screenshots, original live files, database backups, plugin
snapshots and both engine packages are under:
`$XDG_STATE_HOME/easyeffects-widget-fix/<timestamp>/` (normally
`~/.local/state/easyeffects-widget-fix/<timestamp>/`).

`deployed-files.json` records the eight scoped live file hashes. To restore a file,
compare it with that hash before copying its corresponding `live/` backup; preserve
any subsequent edits. The previous engine package is available under `engine/`.
The native bypass-reset setting can be restored through EasyEffects Preferences.

The private fixture uses harmless socket responses and a device-free PipeWire
server. Rerun with:

```sh
xvfb-run -a -s '-screen 0 900x400x24' dbus-run-session -- python3 tests/easyeffects_integration.py
```
