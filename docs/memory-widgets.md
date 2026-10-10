# Memory widgets

The memory tiles resolve their helpers with `$HOME/.local/bin` prepended to
`PATH`. Existing workstation helpers retain precedence; a clean
[linux-memory-kit](https://github.com/gustarmartins/linux-memory-kit) desktop
installation supplies the commands in `/usr/local/bin`.

The Recompress tile runs the selected tier on eligible idle pages with left-click
and selects Zstd 3, 9 or 15 with right-click. For all eligible resident pages,
use `sudo memkit recompress all 1`, `all 2`, or `all 3` in a terminal.

Guarded Writeback uses the installed idle-age and write-budget policy.
Its right-click emergency action bypasses the normal quota after reporting a
warning. ZRAM Algo stages a new primary with left-click; its alternate action
rebuilds ZRAM through the helper's headroom checks. Changing the primary is not
required for recompression.

The installed helpers use `sudo -n` for privileged actions. Configure the
account's authorization deliberately; this UI does not grant sudo access.

Run `python3 tests/memory_widgets_ui.py` to instantiate all seven real tile
models with fake actions in a private home and D-Bus session. The test covers
status, both click paths, tier refresh, and legacy/system helper discovery.
It does not change the desktop's memory policy or require a visible window.
