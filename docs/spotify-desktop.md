# Spotify desktop investigation

Ctrl+Super+R runs `hyprctl reload` followed by
`qs -c ii ipc call shellControl reload`. This uses `Quickshell.reload(false)`
in the existing process and keeps its D-Bus StatusNotifierWatcher alive.
Verified: Spotify stayed minimized through a reload with the same tray owner.
Hyprland configuration and both desktop entry files validate.

The installed official Spotify version 1.3.4.258 matches the signed repository.
Native Wayland was demonstrated with DISPLAY unset and --ozone-platform=wayland.
The GPU process used amdgpu renderD128 and Mesa EGL/Gallium. Both monitors run
at approximately 144 Hz; application FPS was not measured.

Native Wayland is NOT yet qualified. Playback and profile/settings loading
stalled after restarts, including in an XWayland comparison. Playback recovered
once under XWayland after the owner pressed Play, but later restarts stalled
again. The PulseAudio backend experiment also did not immediately resolve it.
The core thread was observed consuming almost one CPU core with no syscalls
in a bounded sample, while the local-file scanner traversed osu! song folders.
This is a lead, not a proven cause.

The persistent native-Wayland launcher changes were rolled back. The active
experimental process may differ from the persistent launcher configuration.
Current preferences, local-file index, and watch-source list are retained under
~/.local/state/spotify-desktop-fix/. No account reset or cache deletion was done.
The first process ignored Quit and SIGTERM and required a targeted SIGKILL.
The same fallback was needed during some later trials.

Quickshell reload API:
https://quickshell.org/docs/v0.2.1/types/Quickshell/Quickshell/#func.reload
