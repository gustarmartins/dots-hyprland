# The fontctl type collection

Twenty complete profiles, each with UI, monospace, title, number, reading and
expressive families. They reference installed fonts; no font files or personal
configuration are bundled. The original six profiles remain available.

Open [the interactive specimen page](font-specimens.html) in a browser to compare
styles, edit the sample headline, resize specimens, filter moods and switch
between dark and paper backgrounds. It reads installed fonts without networking.
Browser specimens illustrate the pairings; they are not desktop screenshots.

```bash
fontctl preset list
fontctl preset atelier --preview       # Read-only; also reports missing families
fontctl preset atelier                 # Apply; asks for system Fontconfig elevation
fontctl preset editorial --user-only   # Apply without system Fontconfig changes
fontctl preset orbit-10pt              # UI, mono, title AND Kitty at 10 pt
fontctl preset arcade --subpixel none  # Grayscale instead of the RGB default
```

Preview makes no settings changes and does not restart anything. Applying follows
the existing backup and desktop update flow, including restarting Quickshell if
it is running. No profile is applied merely by installing the collection.
`--user-only` still applies user settings and restarts a running Quickshell.
It also updates browser defaults using the `fontctl-browser` companion, which
must be installed beside `fontctl`. `fontctl sync-browsers` reapplies the current
Fontconfig families to browsers without restarting the shell.

## Browser and rendering coverage

Firefox profiles are discovered under `~/.mozilla/firefox`, the XDG configuration
directory, Flatpak and Snap. Relative and absolute `profiles.ini` entries and
secondary profiles are included. A managed block in each `user.js` selects the
Western/Unicode sans and monospace defaults and allows websites to use their own
fonts. Serif remains the system serif family. Existing sizes, zoom, non-Latin
choices, security preferences and unrelated user.js content are retained.
Firefox reads these changes on its next start; `prefs.js` is never edited while
Firefox owns it. `fontctl status` distinguishes startup settings from last-saved
preferences and reports running profiles. It does not claim live rendering proof.

Chrome, Chromium, Brave, Edge and Vivaldi profiles receive standard/sans/serif/fixed
defaults in `Preferences`, for both Common (`Zyyy`) and Latin (`Latn`) scripts.
Chromium 156 otherwise rendered the Latin sample as Arial despite a saved Fira
Sans Common preference. This includes common Flatpak/Snap locations. Website
fonts, non-Latin families, sizes, zoom, accounts and extensions are retained.
Only the known legacy Roboto assignment to math/cursive/fantasy is removed.
Busy Chromium profiles are **not written**: close that browser and run
`fontctl sync-browsers`. An incomplete apply returns a failure instead of claiming
success. New profiles are discovered on the next apply; there is no watcher.

Browser changes have private, timestamped backups under
`~/.config/fontctl/backups/*-browsers/`, with absolute source paths mirrored inside
each backup. A `.created` marker records a newly created file. Restore only the
files you intend to roll back, with the affected browser closed.

Fontconfig and GTK carry hinting, RGB/grayscale AA and LCD filtering. GTK keys
are created when missing, including GTK4, and `hintnone` disables hinting.
Firefox uses normal WebRender subpixel eligibility instead of forcing extra
layers. Grayscale disables WebRender subpixel AA. Firefox 150+ also receives
sRGB glyph preblending (`gfx.font_rendering.freetype.gamma=0`, contrast `100`),
addressing Linux dark-text color fringing described in
[Mozilla bug 1910291](https://bugzilla.mozilla.org/show_bug.cgi?id=1910291).
This is text blending, not a display gamma or color-profile change.

Website webfonts and explicit families remain under page control, as described
by [Mozilla](https://support.mozilla.org/en-US/kb/change-fonts-and-colors-websites-use)
and [Chrome's font settings API](https://developer.chrome.com/docs/extensions/reference/api/fontSettings).
No universal CSS overrides or browser security changes are installed. Kitty and
Qt Quick do not promise the same RGB LCD rendering as a browser. Physical
appearance still needs checking on the intended screen.

Super+I → Desktop font profiles exposes hinting, grayscale rendering and a
"Check applied fonts" readout. A sensible native-scale 1080p starting point is
`fontctl preset humanist --kitty-size 12`: Fira Sans 11 pt, Hack 12 pt, full
hinting and RGB. Browser CSS sizes remain independent of desktop point sizes.

Run `python3 tests/test_fontctl_browsers.py` for isolated profile discovery,
content preservation, rendering-only behavior, active-profile protection,
backup/idempotence and GTK missing-key regressions.

All profiles retain the existing full-hinting/RGB default. Use `--subpixel none`
for grayscale. Each profile has deliberate sizes; append `-10pt` to any font
profile for uniform 10 pt, or override sizes after the name. `--mono-size` also
sets Kitty unless a later `--kitty-size` overrides it. The Material Symbols icon
family is never part of these profile assignments.

## Choose a mood

Start with **atelier** for gentle daily use, **orbit** for a futuristic feel,
**editorial** for serif contrast, or **arcade** for pixel headings over readable
UI text. **accessible** uses distinguishable letterforms and larger defaults;
comfort and accessibility still depend on your eyes, display and application.

| Profile | Mood | UI | Monospace | Titles | UI / mono / title / Kitty pt |
|---|---|---|---|---|---|
| `atelier` | Quiet studio; soft geometry and literary accents | Readex Pro | JetBrainsMono Nerd Font Mono | Noto Serif Display | 11 / 12 / 13 / 11 |
| `swiss` | Swiss grid; restrained and precise | Nimbus Sans | Hack | Nimbus Sans | 11 / 12 / 12 / 11 |
| `nord` | Cool minimalism; clean native desktop | Adwaita Sans | Adwaita Mono | Inter Display | 11 / 12 / 12 / 11 |
| `humanist` | Warm open shapes for a working day | Fira Sans | Hack | Fira Sans | 11 / 12 / 12 / 11 |
| `redhat` | Coherent text, display and code family | Red Hat Text | Red Hat Mono | Red Hat Display | 11 / 12 / 13 / 11 |
| `oneplus` | Airy mobile polish with narrow code | OnePlus Sans Text | Iosevka Nerd Font Mono | OnePlus Sans Display | 11 / 12 / 13 / 11 |
| `orbit` | Space-age headings; grounded everyday text | Space Grotesk | JetBrainsMono Nerd Font Mono | Orbitron | 11 / 12 / 12 / 11 |
| `rubik` | Playful rounded geometry, grown-up proportions | Rubik | RobotoMono Nerd Font Mono | Rubik | 11 / 12 / 13 / 11 |
| `orchard` | Soft rounded Apple surfaces | SF Pro Rounded | SF Mono | SF Pro Rounded | 11 / 12 / 13 / 11 |
| `compact` | Small-screen Apple precision | SF Compact Text | SF Mono | SF Compact Display | 10 / 11 / 12 / 11 |
| `editorial` | Magazine contrast; neutral UI and elegant serifs | Noto Sans | Iosevka Nerd Font Mono | Noto Serif Display | 11 / 12 / 13 / 11 |
| `paperback` | A bookish serif desktop with warm display type | Noto Serif | Noto Sans Mono | URW Bookman | 11 / 12 / 13 / 11 |
| `slab` | Confident slab-serif accents and familiar UI | Roboto | RobotoMono Nerd Font Mono | Roboto Slab | 11 / 12 / 13 / 11 |
| `accessible` | Distinct letterforms and generous reading sizes | Atkinson Hyperlegible | AtkynsonMono Nerd Font Mono | Atkinson Hyperlegible | 12 / 13 / 14 / 12 |
| `terminal` | An all-monospace cockpit; tall and compact | Iosevka | Iosevka Nerd Font Mono | Iosevka | 12 / 12 / 13 / 11 |
| `blueprint` | Drafting-board precision with geometric headings | Iosevka | JetBrainsMono Nerd Font Mono | Space Grotesk | 11 / 12 / 13 / 11 |
| `metropolis` | Condensed urban typography for dense panels | Roboto Condensed | RobotoMono Nerd Font Mono | Fira Sans Condensed | 11 / 12 / 13 / 11 |
| `bauhaus` | Geometric modernism with a typewriter counterpoint | URW Gothic | Liberation Mono | URW Gothic | 11 / 12 / 13 / 11 |
| `arcade` | Pixel display accents over friendly readable UI | Rubik | Iosevka Nerd Font Mono | Pixelon | 11 / 12 / 15 / 11 |
| `journal` | Open, unhurried UI with newspaper-style headings | Open Sans | Liberation Mono | Noto Serif Display | 11 / 12 / 14 / 11 |

## Font availability

Every family in all 20 profiles resolved exactly on the authoring workstation.
Another machine may need optional fonts. `--preview` reports a missing family
and the fallback Fontconfig would select; it does not install fonts. Package
names below are the locally verified owners, not a promise of availability in
another distribution or repository. No new packages were needed for this set.

| Installed family | Package owner on the authoring workstation |
|---|---|
| Adwaita Mono | `adwaita-fonts` |
| Adwaita Sans | `adwaita-fonts` |
| Atkinson Hyperlegible | `otf-atkinson-hyperlegible` |
| AtkynsonMono Nerd Font Mono | `otf-atkinsonhyperlegiblemono-nerd` |
| Fira Sans | `ttf-fira-sans` |
| Fira Sans Condensed | `ttf-fira-sans` |
| Hack | `ttf-hack` |
| Inter Display | `inter-font` |
| Iosevka | `ttc-iosevka` |
| Iosevka Nerd Font Mono | `ttf-iosevka-nerd` |
| JetBrainsMono Nerd Font Mono | `ttf-jetbrains-mono-nerd` |
| Liberation Mono | `ttf-liberation` |
| Nimbus Sans | `gsfonts` |
| Noto Sans | `noto-fonts` |
| Noto Sans Mono | `noto-fonts` |
| Noto Serif | `noto-fonts` |
| Noto Serif Display | `noto-fonts` |
| OnePlus Sans Display | `locally installed` |
| OnePlus Sans Text | `locally installed` |
| Open Sans | `locally installed` |
| Orbitron | `locally installed` |
| Pixelon | `locally installed` |
| Readex Pro | `ttf-readex-pro` |
| Red Hat Display | `redhat-fonts` |
| Red Hat Mono | `redhat-fonts` |
| Red Hat Text | `redhat-fonts` |
| Roboto | `ttf-roboto` |
| Roboto Condensed | `ttf-roboto` |
| Roboto Slab | `ttf-roboto-slab` |
| RobotoMono Nerd Font Mono | `ttf-roboto-mono-nerd` |
| Rubik | `ttf-rubik-vf` |
| SF Compact Display | `apple-fonts` |
| SF Compact Rounded | `apple-fonts` |
| SF Compact Text | `apple-fonts` |
| SF Mono | `apple-fonts` |
| SF Pro Rounded | `apple-fonts` |
| SF Pro Text | `apple-fonts` |
| Space Grotesk | `otf-space-grotesk` |
| URW Bookman | `gsfonts` |
| URW Gothic | `gsfonts` |

“locally installed” means that the font file is not owned by a Pacman package.
Apple and OnePlus names refer to separately installed fonts; obtain and use
those fonts under their own licenses. These profiles do not redistribute them.
A font resolved by Fontconfig can still look different in Kitty, GTK, Qt Quick
or a browser. Kitty and Qt Quick distance-field text do not use RGB LCD AA.

## Maintenance and validation

The canonical profile definitions are the `curated_presets` table in
`dots/.local/bin/fontctl`. Keep this guide and the specimen page in sync when
editing that table. The collection was checked with Bash syntax, ShellCheck,
all 20 standard and 20 compact previews, installed-family matching, explicit
size/rendering overrides and invalid-input rejection. Desktop configuration
hashes stayed unchanged during previews. File generation is checked separately
using disposable fixtures; physical desktop appearance remains user-selected.
