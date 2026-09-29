# Quickshell responsiveness repair — 2026-09-22

The resource popup is responsive and closes promptly after the live deployment,
confirmed by the user. Workspace tracking is updating again. This is a repair of
the reproduced bar failures, not a claim that every shell surface has been profiled.

## Starting state and documentation

- Fork HEAD and origin/main: `2af30a94`; checkout clean before this work. The live
  QML matched the fork (only a generated Python cache differed). The bare home
  config repository contained earlier unsynchronized changes; those were preserved.
- Engine: upstream `c6a516096dd84d5255b409482eb4bf740b952f88`, Quickshell 0.3.1,
  packaged as `0.3.1.r14.gc6a5160-2` with two local patches. Hyprland: 0.56.2,
  `efb50993780079460b0cbed1363e2166a2de1d9f`. Qt: 6.11.2.
- Refreshed upstream dots to `2f0c8bf4`. Its intervening history is predominantly
  distribution packaging; there is no upstream popup/reconnection fix to import.
- No Hyprland MCP tool was exposed in this session. The check used the **exact
  pinned engine source**, local Hyprland source, and official documentation:
  [LazyLoader](https://quickshell.org/docs/v0.3.0/types/Quickshell/LazyLoader/),
  [FileView](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/FileView/),
  [Hyprland IPC](https://wiki.hypr.land/IPC/), and
  [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html).

For future checks, read the recipe's `_commit` and local patches before using
current/master API documentation. The matched source was available under
`~/.local/state/quickshell-upgrade-20260918/source`. In particular:

```sh
python3 tools/quickshell-reference.py --source /path/to/matched/engine deleteOnInvisible activeAsync
```

This read-only checker prints the running versions and official references, and
refuses to search a checkout whose revision or applied patches do not match the
fork recipe. `QS_SOURCE_DIR` can supply the checkout path.

| Question | Matched source |
| --- | --- |
| Does a disconnected compositor event stream reconnect? | `src/wayland/hyprland/ipc/connection.cpp` |
| Does hiding a layer window retain its renderer? | `src/wayland/wlr_layershell/wlr_layershell.cpp`, `deleteOnInvisible()` |
| Does `LazyLoader.active` block or reuse objects? | `src/core/lazyloader.hpp` and `.cpp` |
| When is a proc-file read ready? | `src/io/fileview.hpp` and `.cpp` |

## Causes and changes

1. **Permanent stale state after socket loss.** Two consecutive live shell
   processes logged `Hyprland event socket error: QLocalSocket::PeerClosedError`
   shortly after startup. The engine never retried. The GUI could answer IPC
   while its native workspace model remained permanently stale. Native patch
   `0003` reconnects with 250 ms–5 s backoff, resets partial stream data, and
   reconciles monitors, workspaces, windows and active-window focus. Windows
   destroyed during disconnection are removed from the model. A live disconnect
   after deployment also recovered with workspace IDs matching the compositor.
2. **Popup construction and renderer teardown on input.** `StyledPopup.active`
   followed `MouseArea.containsMouse`, forcing synchronous creation/destruction
   on each press/release. A live trace captured a 3.044 s UI-thread futex wait.
   Retaining only the QML object was insufficient: this engine deliberately
   destroys a layer window when `visible` becomes false, to avoid a Qt Wayland
   protocol bug. Popups now load QML asynchronously and, after first use, keep
   their native window. Closing clears all painted content, input region and
   blur, with no keyboard focus or exclusive zone. The screen follows the anchor
   bar. This spends some retained memory on previously opened popups to avoid
   repeated render-thread/context creation and destruction. The trace alone did
   not resolve the exact native stack of the original 3 s wait.
3. **Redundant native snapshots on focus events.** Native models already handle
   `activewindow`/`activewindowv2`; the compatibility layer no longer fetches every
   monitor, workspace and client again for those events. Title snapshots remain
   capped at four per second because some compatibility consumers still read
   `lastIpcObject.title`. A read-only `hyprlandDiagnostics.status` IPC method makes
   native workspace state inspectable without changing focus.
4. **Stale resource values and process overhead.** The resource timer reloaded
   asynchronous FileViews and immediately parsed the previous contents. Parsing
   and history updates now run on read completion. GPU and CPU-frequency reads
   remain in child processes, use shell builtins instead of seventeen additional
   `cat`/`sort`/`tail` children per tick, and do not overlap. CPU accounting treats
   iowait as idle and includes steal time. The five-minute memory PSI parser now
   reads `avg300` from the same `some` line correctly.
5. **Oversized cover-art command.** A live warning contained roughly a megabyte
   of base64 art passed to `bash -c`, exceeding Linux's per-argument limit.
   File URLs go directly to Qt. Data and remote URLs go to a bounded, atomic
   cache helper over stdin, so artwork payloads never enter process arguments
   or logs. This also gives the native color quantizer the local file it needs;
   sending a data URL directly to it produced another large warning. Failures
   are not marked successful, and a changed track waits for the prior download
   before requesting the newest art. Images decode asynchronously with a bounded
   requested size.
6. **Notification teardown warnings.** Live dismissal exposed delegates reading
   summary/image/urgency/actions after their notification object was destroyed.
   These bindings and action callbacks now tolerate the cleared object. The
   group mouse handler also declares its event argument explicitly.

The host was not completely idle: initial I/O PSI was approximately 35% some /
23% full despite low memory pressure. This is relevant background evidence, not
an explanation for accepting a permanently stale shell. No swap, memory policy,
compositor settings, player selection or audio service was changed.

## Validation and limits

- Native socket fixture fails against the previous engine and passes against
  the patched build and packaged executable: initially absent listener, missed
  window/workspace changes, partial event, repeated reconnect, empty active
  window, and no periodic polling on a healthy connection.
- Nine upstream CTest suites pass. Private PipeWire regression: 20 cycles / 240
  transitions pass, including the packaged executable.
- Private KWin → Hyprland test uses two outputs and actual production popup and
  resource components. Eight open/close cycles created 16 popup QML objects
  before, 2 afterward. After closing, retained windows were mapped with no
  painted children and an empty input region; each followed its own monitor.
  CPU/RAM/GPU/frequency samples and workspace changes continued to update.
- Popup screenshots were inspected. CLI timings include process launch and
  nested-compositor overhead; they are not click-to-photon measurements.
- Existing background placement (51 assertions) and fullscreen state (10
  assertions) pass.
- The artwork/notification QML regression passes against the final packaged
  executable in a private X server: a 349,642-character data URL is cached
  byte-for-byte, artwork clears correctly, and notification-object removal
  produces no null-object errors. The existing private notification service
  lifecycle/persistence suite also passes.
- Initial live validation retained the existing respawn owner, shell settings
  were exactly unchanged, and output volume was unchanged. A 30-second main-thread
  trace captured a maximum futex wait of 139 ms; a further 60-second sampler did
  not capture a futex wait longer than 250 ms. Neither observation is a universal
  latency guarantee. User acceptance covers the resource popup's opening/closing.

Rerun the focused checks:

```sh
QS_TEST_BINARY=/path/to/quickshell python3 sdata/dist-arch/illogical-impulse-quickshell-git/tests/hyprland-reconnect.py
QS_TEST_BINARY=/path/to/quickshell dbus-run-session -- python3 tests/quickshell_bar_performance.py
QS_TEST_BINARY=/path/to/quickshell xvfb-run -a dbus-run-session -- python3 tests/quickshell_media_lifecycle.py
qs -c ii ipc call hyprlandDiagnostics status
hyprctl -j monitors
```

`eventAgeMs` measures time since the last event, not latency: a quiet compositor
can legitimately produce a large value. Compare workspace identities with live
compositor state before diagnosing a frozen event stream.

Workstation receipts, pre-change files/package, installed hashes and guarded
rollback: `~/.local/state/quickshell-performance-20260922/`. `rollback.py` refuses
to overwrite later QML edits or replace a subsequently changed engine. It restores
these six QML files and the prior engine package, removes the added artwork
helper, and retains the existing respawn owner. The final package is
`0.3.1.r14.gc6a5160-3`, built with the complete package recipe and its checks.

Unrelated BlueZ/PowerProfiles warnings and occasional ShaderEffect/SVG warnings
remain outside these verified repairs. No services were enabled to suppress them.

The full Settings/sidebar/overview interaction paths and fullscreen bar creation
have not been latency-qualified by this test. Their layer-window lifecycles are
the next places to measure if similar stalls remain; do not blindly retain every
fullscreen surface, since that can affect compositor scanout behavior.
