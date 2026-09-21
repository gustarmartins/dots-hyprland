# Background widget placement across monitors

Clock and weather shared saved coordinates, but their canvas moved according to
the global workspace number. Workspace 1 on one monitor and workspace 6 on another
therefore showed different positions. Dragging inside that translated canvas
could save negative coordinates; startup clamped both widgets to the same edge,
causing overlap. Dragging also replaced coordinate bindings, so the result could
differ before and after restarting the shell.

Manual widget positions now use screen coordinates. The canvas translation is
cancelled without a second position animation, and dragging saves bounded screen
coordinates before restoring the position bindings. Equal-size monitors share
the same layout across workspaces and restarts. Digital text alignment uses the
screen position as well. The centered lock clock still
uses each screen's dimensions. Existing automatic placement remains available.

Wallpaper parallax now uses each monitor's configured contiguous workspace range.
For assignments 1–5 and 6–10, workspaces 1/6 share the start, 3/8 the midpoint, and
5/10 the end. Repeated ranges such as 11–15 and 16–20 start independently. Rules
are read once at shell startup and again on compositor configuration reload;
opening or closing applications cannot shift the range. Numeric rules with exact
monitor names are supported. Unassigned or selector-based rules fall back to the
configured workspace count.

## Validation

- `node tests/background_workspace_placement.cjs`: 51 assertions covering three
  monitor names, repeated ranges, duplicate/unrelated/disabled rules, single
  workspaces and unassigned-workspace fallback.
- Private virtual KWin plus nested Hyprland loaded the production background,
  clock and weather components on two 1920 × 1080 outputs. Tests covered paired
  workspaces 1/6, 2/7, 5/10 and 11/16, sampled positions during animation, real Qt
  pointer dragging, shared saved
  coordinates, process restart, lock centering after dragging, unlock restoration,
  bounded coordinates, adding/removing a third output, and digital clock
  alignment and placement across workspace switches.
- Captures were inspected for the separated widgets. Weather data was fixed in
  the fixture; no network or live desktop input was required.

The local configuration repair translates the existing saved widget positions
together using workspace 1 as the reference. It preserves their relative spacing
and vertical placement. These personal coordinates are not distributed in the
repository. Physical-monitor visual acceptance remains separate from the private
compositor checks.

The binding restoration follows [Qt's property binding rules](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html#creating-property-bindings-from-javascript).
