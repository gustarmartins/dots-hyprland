# Gustarmartins desktop profile

This branch is a reproducible, public-safe snapshot of the Arch/Hyprland
desktop profile currently used on the maintainer's desktop. It keeps End-4's
normal installer and adds the matching Hyprland Lua configuration, Quickshell
layout, and lightweight user helpers.

## Install

On a fresh Arch installation:

```bash
git clone https://github.com/gustarmartins/dots-hyprland.git
cd dots-hyprland
./setup install
```

The installer remains interactive, backs up clashes, installs the repository's
dependencies, and copies the profile. The shell's current layout template uses
`@HOME@` placeholders which are replaced with the installing user's home path.

For a file-only test or refresh, use the upstream-supported command:

```bash
./setup install-files
```

On an existing installation, the personal Quickshell settings file is written
as `~/.config/illogical-impulse/config.json.new` instead of silently replacing
the existing file.

## Official font utility

`fontctl` is installed into `~/.local/bin` by `./setup install` and is the
profile's supported way to keep font families and rendering coherent across
Fontconfig, GTK, KDE, Quickshell, Kitty, and Firefox.

```bash
fontctl status
fontctl preset list
fontctl preset apple
fontctl set --ui "SF Pro" --mono "SF Mono" --mono-size 13
fontctl fix-rendering
```

System-wide Fontconfig changes request elevation through `pkexec`. Quickshell
is restarted after an applied change; Hyprland is intentionally left running.

## What is intentionally not automatic

- Monitor declarations and wallpaper files are machine-local.
- OBS credentials, mail/OAuth configuration, shell history, device addresses,
  and other private state are not published.
- Root-only ZRAM, NVMe writeback, sysctl, GPU, and Focus Mode backends are
  hardware-specific. Their UI helpers fail safely when those backends are not
  installed, but this repository does not apply privileged tuning to another
  machine automatically.
- The display-resume unit under `system/` is a user template. If its monitor
  profile is appropriate for a machine, install and enable it explicitly as
  `display-resume-fix@$USER.service`.
- `Super+F9` uses `obsctl`: capture sources are activated only for an actual
  recording and the empty scene is restored after stopping.

The result is the same visible Hyprland/Quickshell profile without copying
machine identity, credentials, caches, recordings, or storage-specific policy.
