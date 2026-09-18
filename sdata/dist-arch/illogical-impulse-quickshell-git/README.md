# Pinned Mekki Quickshell package

Native engine pinned to upstream `c6a516096dd84d5255b409482eb4bf740b952f88`
(2026-09-15; 0.3.1 plus 14 fixes), retaining illogical-impulse dependencies.
This package does not replace or import the user's desktop QML configuration.

Local patches:

- `0001`: cache the PipeWire node's QML interface using `QPointer`. An interface
  can be destroyed before all default-node destruction callbacks run; reentrant
  bindings must receive null instead of the freed cached pointer. This fixes a
  second lifetime failure beyond upstream's targeted-default-disconnect fix.
- `0002`: wait for asynchronous popup polish in the existing position test,
  retaining the original expected coordinates.

The build rejects stale or unpatched trees when the maintenance helper tries
`--noextract`, allowing its normal fresh-source fallback to adopt the new pin.

`makepkg` builds with two jobs by default (override
`CMAKE_BUILD_PARALLEL_LEVEL`) and runs all nine upstream test suites. Debug
symbols stay in the binary. The compatibility hook runs after Qt Base,
Declarative and Wayland updates; rebuild this package after an ABI mismatch.

Before installing a changed pin, run the additional device-lifetime regression:

```sh
tests/run-pipewire-regression.sh /path/to/built/quickshell
```

It starts a private, hardware-free PipeWire server, exercises 20 cycles across
source and sink defaults (240 transitions), and stops its own server. It needs
Python 3 and PipeWire tools; no root or desktop audio restart is used. Receipts
are retained in the printed temporary directory. The prior installed 0.2.1 and
unpatched current upstream both failed the first cycle; the guarded cache passes.

Validated 2026-09-18 against Qt 6.11.2: nine upstream suites, private PipeWire
regression, both custom panel-family component trees, Settings rendering and
saved-settings toggle round trip, and read-only live Hyprland Lua/PipeWire/tray
integration. Deployment report and rollback package on this workstation:
`~/.local/state/quickshell-upgrade-20260918/UPGRADE.md`.
