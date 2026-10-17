# Desktop feature integration

Super+I is the settings entry point for new desktop features. Provide a master
switch that stops background work owned by the integration, separate controls
for useful features, and a searchable settings destination. Hide optional feature
controls while disabled. Account setup, credentials and service infrastructure
belong in their owning application/helper; expose concise status and shortcuts.

Requests often start from the home directory. Inspect both this repository and the live
configuration before editing. Apply scoped changes to each, preserving unrelated
differences and other work. Do not publish account data, tokens or mail contents.

Treat task-specific Hyprland focus/activation guards as temporary. Revert your
own guards when the work finishes, restoring the exact previous settings while
preserving user configuration and concurrent changes.

Run relevant tests under `tests/`. QML UI tests use a disposable home and private
D-Bus session; keep them separate from the real desktop and mail accounts.
