# Desktop effects and Material shell revision — 2026-09-13

Open **Super+I → Desktop effects**, or use the **Desktop mood** selector in the
right sidebar. Presets apply immediately; individual controls are a draft until
**Apply custom changes** is pressed. Reset edits reloads the applied state.

To keep a custom look, apply any pending edits, enter a name, and press
**Save current preset**. A named chip appears beside the built-in presets;
clicking it restores the entire saved effects configuration. Saving itself does
not apply or change effects. Names are limited to 32 characters and must be
unique, ignoring case. Saved chips persist in
`~/.config/desktop-effects/presets.json` across Settings and desktop restarts.
The CLI equivalents are `desktop-effects save 'My look'`,
`desktop-effects presets`, and `desktop-effects preset saved:<id>`.

- Light: no blur, motion blur, glow, shadows, ambient animation or rotating borders.
- Balanced: two-pass wallpaper glass and softer motion, without continuous effects.
- Cinematic: live glass, motion blur, spring transitions and rotating borders.
- Aurora: animated colored light, stars and vertical workspace transitions.

Aurora now uses 6 px outer gaps after Gustavo's spacing correction. The current
custom settings may differ from a preset; switching presets deliberately replaces
the whole effects configuration. The separate Background page's existing
parallax preference remains independent: either parallax switch enables it.

The backend is `~/.local/bin/desktop-effects`. It validates input and the generated
Lua with the installed Hyprland before applying. Settings live in
`~/.local/state/desktop-effects/state.json`; the compositor module is
`~/.config/hypr/custom/cinematic-effects.lua`. An advisory lock serializes changes.
Live reload failures restore the previous Lua module. Shell state is written only
after a successful compositor reload.

```sh
desktop-effects status
desktop-effects preset light
desktop-effects preset aurora
```

## Shell changes

The right sidebar separates Controls, Inbox and Agenda. Desktop mood has a direct
preset selector. Surface colors use Material roles; controls use 64 px cells,
consistent rounded shapes, stronger label weights and wrapped names. The two
sidebars share 16 px padding and 28 px outer corners. Notifications use 24 px
container corners and a distinct translucent popup surface. Popup and sidebar
opacity are configurable from Desktop effects.

Notification groups use a bounded scrolling viewport instead of assigning the
list the combined height of every email. Expanded bodies and actions are loaded
asynchronously on demand. Styled text replaces the more expensive RichText
renderer; hyperlinks, actions and the original body used for Copy remain.
Popup blur has its own low alpha threshold instead of inheriting the shell's
0.79 cutoff. Fullscreen and lock gates unload the animated wallpaper overlay.

## Validation and limits

- All four presets, palette choices and window/workspace styles pass the installed
  Hyprland's config validator. Invalid numeric and enum inputs are rejected.
- GUI test on isolated Xvfb: incrementing ambient intensity and pressing Apply
  changed only that field; the previous intensity was restored.
- Synthetic 300-email test: the old expanded group instantiated 300 cards;
  the revised group instantiated 2 initially and 3 after scrolling to the end.
  Its model still contained all 300 messages. This is evidence of bounded
  rendering work, not a measured live email frame-time improvement.
- Settings/sidebar previews loaded without QML errors; compositor configerrors
  was empty. Existing unrelated shell warnings remain.
- Gustavo reported Eden maintaining a clean 72 fps while the heavy effects were
  active. No claim of measured 144 fps desktop animation is made.
- Test logs and preview: `~/.local/state/desktop-effects/validation-20260913/`.

## Rollback

The pre-revamp snapshots are on branch
`backup/desktop-before-revamp-20260913-000821` in both remotes:

- arch-sync: `2844d024789b71347f41599ef21f437822498b85`
- dots-hyprland: `67f511e6fc7f980c5a5aab2a584e7c1340e8cef3`

Local archive:
`~/.local/state/desktop-effects/backups/20260913-000821/desktop.tar.gz`.
Use Light for an immediate lighter desktop. Restoring source files should be
scoped to the files you intend to revert so later changes are preserved.

## RAM residency audit

One sample showed Hyprland at about 45 MiB RSS + 82 MiB swap and Quickshell at
579 MiB RSS + 22 MiB swap, with approximately 3.7 GiB available system RAM.
These are changing snapshots, and RSS plus swap does not predict the cost of
locking every virtual mapping. Both processes shared session-3.scope with other
applications. No memory policy was changed.

A dedicated desktop cgroup at launch can disable new swapping and give the
working set reclaim protection. This is different from true mlock residency;
mlock needs in-process support (and adequate limits), while an external process
cannot simply mlock another process's address space. Avoid applying the policy
to the whole session or using live debugger injection into the compositor.

References: [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html),
[Hyprland animations](https://wiki.hypr.land/configuring/core/animations/),
[Linux mlock](https://man7.org/linux/man-pages/man2/mlock.2.html).
