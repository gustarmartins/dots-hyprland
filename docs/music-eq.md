# Automatic music EQ

Super+I → Audio → Automatic music EQ controls `music-eq.service`.
The master switch stops/starts the watcher. Source and fallback switches appear
only while enabled. `music-eq status` reports service state and its last decision;
`music-eq disable` stops it and restores the prior preset if it still owns the
current selection. Manual preset changes last until the next song.

Dependencies: EasyEffects with its local command socket, Python, python-gobject,
Playerctl GI bindings, WirePlumber (`wpctl`), a user D-Bus session and systemd.
The existing EasyEffects instance must be running. The watcher neither starts
nor restarts the audio stack. Spotify desktop supplies MPRIS. Jukebox uses mpv's
MPRIS plugin; its process must have a jukebox input-IPC argument. Generic mpv
video players are excluded. No Spotify account/API credentials are needed.

Install `dots/.local/bin/music-eq`, `dots/.config/systemd/user/music-eq.service`,
and the QML changes using the repository's normal dotfile workflow, then run
`systemctl --user daemon-reload`. Configure `~/.config/music-eq/config.json`
before enabling on a new machine:

```json
{
  "spotify": true, "jukebox": true, "artists": true, "genres": true,
  "tracks": [{"artist": "Artist", "title": "Song", "preset": "measured-preset"}],
  "artist_rules": {}, "genre_rules": {},
  "fallback": "saved-baseline-preset",
  "route": "your-output-node-name"
}
```

All referenced presets must exist in the EasyEffects output directory and have
`limiter#0`. Song rules win over artist rules, genre rules, then the baseline.
Matching preserves title/version suffixes. Artist and genre choices are style
approximations, not measurements of every song. Spotify often supplies no genre;
known song/artist rules still work. Multiple playing players, missing metadata,
a different configured output, manual bypass and active `astra-profiled` suspend
selection. `wpctl inspect @DEFAULT_AUDIO_SINK@` identifies the output node; a
physical headphone change on the same analog jack cannot be detected.

The watcher preserves final limiter output gain and snapshots exposed live
controls before its first change. Mid/side channel controls are not readable
through this EasyEffects socket: save those edits before enabling; restoration
uses their saved preset values. Diagnostics and the last restoration snapshot
are in `~/.local/state/music-eq/`. Personal rules stay outside this repository.

The local `music-eq-lab` skill includes `scripts/register_rules.py` to register
validated installed songs without changing current playback. Do not replace
measured preset input headroom with the listener's output trim.

Validation:

```sh
python -m unittest discover -s tests -p test_music_eq.py
 dbus-run-session -- python tests/music_eq_mpris.py
python tests/settings_catalog.py
xvfb-run -a dbus-run-session -- python tests/settings_ui.py
```

The MPRIS test uses an isolated bus, fake Spotify and fake EasyEffects socket.
It does not control the owner's players or audio.

Exact local recording rules are supported as `file_rules: {"/absolute/audio.mp3":
"preset-name"}`. They precede tags and apply only to a confirmed Jukebox player.
This handles osu! MP3s with missing or misleading Nightcore tags without changing
the original song on Spotify or the osu! gameplay profile.

### Temporary song overrides

Manual preset selections survive pause/resume, temporary missing metadata,
player reconnection and watcher restarts within the same login session. Pausing
a known song leaves its preset untouched. The watcher uses source plus recording
URI (or track ID/metadata fallback), so corrected tags and player instance names
do not turn the same recording into a new song. A genuinely different recording
or source expires the hold; automation waits for playback before applying it.

Selecting in EasyEffects is detected from live preset changes, including while
paused. The Super+I picker also records explicit selections, including choosing
the same preset again, and wakes the watcher. Both paths preserve persistent song
mappings. Session state is private under XDG_RUNTIME_DIR and does not survive
logout/reboot. Tests cover selection before an immediate pause, paused track
changes, overlap, metadata gaps, reconnection, bypass, restart and next-song expiry.
