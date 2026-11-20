# Temporary app loudness

The **Music loudness** card below Eden boost has an app picker, **− / +**,
**Match loudness** and **Reset**. Pick the app whose audio you want to adjust.
Firefox, other browsers, Spotify, mpv/Jukebox and other playback apps appear
when they have opened an audio stream. A browser selection covers its audio
streams/tabs; this is not a per-tab control. Open playback once and refresh if
an app is not listed. Super+I → Audio exposes the same picker, master switch,
button step, matching target and preset-follow option. Search for “Firefox”,
“app picker”, “music loudness”, “quiet songs”, “gain” or “LUFS”.

Only the selected app's current streams receive extra gain. Unlike the previous
version, this does **not** change the shared EasyEffects limiter's input gain.
It installs a temporary PipeWire linear gain stage inside each selected playback
stream, before the current effects. This avoids changing other apps' gain or
moving streams between sinks. EQ, mid/side, limiter controls, volume controls,
spatial processing, saved presets and Eden's independent boost are preserved.
The selected app must be routed through the current EasyEffects final limiter.
Increasing gain can engage that limiter more strongly. Concurrent sources still
share the existing limiter, so simultaneous peaks can interact through its gain
reduction; per-app gain is not a separate effects/limiter pipeline.

Manual − / + remains available while other apps play. **Match loudness** measures
eight seconds at the final limiter's stereo output with FFmpeg EBU R128/true peak.
Because that output is shared, matching is unavailable while another source feeds
it; the card names the apps to pause. It also cancels if other audio appears
during measurement. Its default target is −16 LUFS. It adds the lesser of missing
loudness and measured peak headroom, leaving 0.5 dB below the existing ceiling.
It never automatically makes a loud track quieter. This is a section measurement,
not a whole-song guarantee or a continuous automatic volume rider. A section
already reaching the ceiling may receive no automatic boost; manual buttons
remain available. Since the gain precedes the effects, nonlinear processors can
change the result; matching does not guarantee an exact output LUFS.

**Auto match loudness** is an optional checkbox on the card and in Super+I →
Audio. It starts the existing worker and checks an eight-second section every
30 seconds by default (15, 30 or 60 seconds in settings). Each check raises or
lowers only the selected app by at most 1 dB, toward the existing matching target.
It leaves differences below 1 LU alone, limits automatic gain to −12…+6 dB,
and caps increases by measured true-peak headroom. Very quiet sections below
−40 LUFS or −55 dBTP are skipped rather than amplified. Paused/missing playback,
another app audibly feeding the shared effects, bypass or a missing limiter suspends
matching. A background game can keep a running stream open while outputting only
silence. Auto mode monitors up to four other stereo playback streams alongside
the same measured section, using extra channels on its temporary meter. It accepts
them only if every monitored channel stays below −80 dBFS for that section.
Any new/replaced stream or changed route cancels the measurement. Microphone/source
nodes are never connected; unsupported background streams still require a pause.
The one-shot Match button retains its existing mixed-audio restriction.
Measurements use one FFmpeg processing thread; no continuous recording
or extra audio processor is installed. These periodic sections approximate
loudness matching, rather than guaranteeing whole-song normalization or preserving
every intentional change in dynamics. The EBU distinguishes short-term and
whole-programme loudness in its [metering guidance](https://tech.ebu.ch/groups/ploud-old).

Manual − / + and Reset turn automatic matching off. Unchecking the box cancels
an automatic measurement and keeps the last app adjustment; Reset removes it.
The normal ownership guard still runs while an adjustment remains. Master off
stops the worker and removes owned gain. Automatic matching starts disabled;
enabling it is explicit. It resumes checking after song/app/preset changes once
the protected route is available again.

MPRIS metadata is optional and is accepted from any player associated with the
selected app, including browser subprocesses. A known song change resets extra
gain. Without metadata, gain lasts for the selected stream session, ending on
Reset, switching apps, closed/replaced streams, output/routing change, lost limiter
or master off. Opening a new browser audio stream ends the current adjustment;
press + again to apply it to the current streams. Pauses retain gain while the
streams and protected route remain. Preset changes retain app gain when enabled,
without adding it again or overwriting a new preset's settings.

The worker operates during an adjustment, measurement or enabled automatic mode.
With auto enabled but no adjustment, it checks local state every five seconds
and attempts a measurement only at the configured interval; otherwise it stops idle.
Off removes its still-owned stream stages, cancels capture, stops the worker and
hides the card. It never starts/restarts EasyEffects, PipeWire or a player.
Exact PipeWire cookie, node serial and process birth identify each owned stream.
Reset preserves externally edited stages. Writes have readback; partial failures
remove successfully applied stages, and failed cleanup retains a recovery receipt.
The previous shared-limiter receipt can be cleaned up with its original ownership
checks. Abrupt session/server termination is not a claim of verified restoration.

Dependencies: Python with Gio (`python-gobject`, optional for song boundaries),
systemd user services, EasyEffects with its local command socket, PipeWire tools
(`pw-dump`, `pw-record`, `pw-link`, `pw-cli`) with stream filter-graph support, and
FFmpeg/ffprobe. The PipeWire linear filter is described in the
[upstream filter-chain documentation](https://docs.pipewire.org/page_module_filter_chain.html).
Install `music-loudness` under `~/.local/bin`, its user unit and QML files, then
run `systemctl --user daemon-reload`. Do not enable the worker at login.

Configuration: `~/.config/music-loudness/config.json`. Private session receipt:
`$XDG_RUNTIME_DIR/music-loudness-session.json`. Diagnostic events under
`~/.local/state/music-loudness/` contain hashed track identities and gain values,
not captured audio. Temporary recordings are deleted after local analysis.
No microphone is auto-connected and no cloud API is used.

```sh
music-loudness status
music-loudness enable
music-loudness select-app exe:firefox  # use an id listed by status
music-loudness adjust 1
music-loudness match
music-loudness auto-match true
music-loudness auto-interval 30
music-loudness auto-match false
music-loudness reset
music-loudness disable
```

Step and target accept explicit finite values. The linear stage supports at most
+20 dB; out-of-range requests are reported rather than silently clamped.

Validation:

```sh
python tests/test_music_loudness.py
python tests/music_loudness_ui.py
python tests/music_loudness_service.py
python tests/music_loudness_native.py
python tests/settings_catalog.py
```

UI tests use a disposable home/private D-Bus bus and inert helper. Native tests
use a separate PipeWire server without hardware or microphone nodes, two real
playback processes and real captures. They verify selected-app gain, unchanged
other-app output, non-stacking adjustments and reset. The native fixture named
`firefox-fixture` is a test player, not a claim of actual Firefox playback testing.

An additional headless Firefox qualification used its real PulseAudio stream on
a private PipeWire server and a disposable browser profile: +6 dB produced
+6 LU, the other app changed by 0 dB, and Reset restored the original level.
Live mpv verification also preserved 261 readable EasyEffects controls. These
checks verify routing/gain behavior, not subjective listening preference.
