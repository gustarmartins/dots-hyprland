# Wallpaper and terminal color system

## Data flow

1. `QuickConfig.qml` selects the wallpaper, light/dark mode, and Material scheme.
2. `Config.qml` persists those choices and the terminal tuning values in
   `~/.config/illogical-impulse/config.json`.
3. `switchwall.sh` serializes color generation, then runs Matugen once. Before
   that run, `prepare_matugen_config.py` excludes outputs that are not writable
   (for example a GTK CSS symlink into `/usr/share`) instead of following the
   symlink as root or aborting after a partial write. Matugen is the source of
   truth for both the selected wallpaper color and Material roles used by
   Quickshell, GTK, Hyprland, Fuzzel, and KDE.
4. `generate_colors_material.py` consumes Matugen's exact source color and
   Material JSON. It derives only the semantic ANSI palette.
5. `render_terminal_theme.py` validates every placeholder and atomically writes:

   - `kitty-theme.conf` for persistent Kitty colors;
   - `sequences.txt` for terminals that support standard OSC colors;
   - `starship.toml` so the prompt uses truecolor Material roles;
   - `enabled`, which tells shell startup files whether terminal theming is on.

6. New Kitty processes read the persistent include. Existing Kitty windows get
   a color-only remote-control update, so changing a palette does not reload
   unrelated runtime state such as per-window font size, scrollback, or layout.
   A full config reload happens only once when terminal theming is disabled, to
   restore the base Kitty colors. Zsh and Fish load the OSC palette and
   generated Starship config when a new interactive shell starts.

## Advanced settings

| Setting | Meaning | Color-safe default |
| --- | --- | --- |
| Shell & utilities | Master switch for Matugen-driven app and shell colors. | On |
| Qt apps | Runs the KDE Material You bridge after generation. | On |
| Terminal | Applies the generated ANSI, Kitty, and Starship colors. | On |
| Force dark terminal palette | Uses dark terminal roles while the desktop is light. | Off |
| Wallpaper tint | Fraction of each ANSI hue's route toward the wallpaper source hue. `0%` preserves canonical red/green/yellow/blue/magenta/cyan. | `15%` |
| Maximum hue shift | Hard cap on wallpaper-driven rotation. This prevents distant colors from collapsing toward one accent. | `15°` |
| ANSI contrast | Moves difficult ANSI tones toward bounded readable targets. It never multiplies tones and cannot wash the palette to white. | `50%` |

The **Full spectrum** preset uses `0% / 0° / 50%`: exact ANSI hue families,
Material background/foreground/selection colors, and strong contrast. The
**Balanced tint** preset uses `15% / 15° / 50%`: the recommended subtle
wallpaper tint while keeping every ANSI family distinct.

Changes in Advanced settings are applied automatically after a short debounce.
Changing a wallpaper, light/dark mode, palette family, or accent color uses the
same generation path.

## Palette guarantees

- ANSI indexes `0-15` are semantic and wallpaper-aware.
- Indexes `16-255` remain the standard xterm color cube and grayscale ramp.
  Starship uses a generated truecolor config instead of stealing grayscale
  indexes from other applications.
- Terminal background, foreground, and cursor are separate roles. Light mode
  therefore no longer makes ANSI black equal to the light background.
- Reapplying an identical Kitty theme is a no-op, and palette changes update
  only colors rather than reloading the whole Kitty configuration.
- Contrast adjustment is bounded. At `100%`, colors move toward safe tone
  targets but retain their hue and chroma.
- `Monochrome` intentionally removes ANSI chroma. Every other Material scheme,
  including Neutral, retains a full semantic terminal palette.

## Verification

Regenerate without changing the wallpaper:

```bash
~/.config/quickshell/ii/scripts/colors/switchwall.sh --noswitch
```

Show all 16 ANSI foreground and background colors:

```bash
for i in {0..15}; do
  printf '\e[38;5;%sm%2s foreground\e[0m  \e[48;5;%sm  background  \e[0m\n' "$i" "$i" "$i"
done
```

Run the palette invariants from the repository:

```bash
"$ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/python" -m unittest -v tests/test_terminal_colors.py
```
