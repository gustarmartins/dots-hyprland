# Stinger presets and Eden boost

Five local EasyEffects output presets extend the existing Stinger chain:
`codex-stinger-warm-immersive`, `codex-stinger-kick-focus`,
`codex-stinger-mid-focus`, `codex-stinger-detail-focus`, and
`codex-stinger-air-focus`. Warm Immersive emphasizes bass body and brings the
mids forward with restrained stereo width. Kick emphasizes impact over rumble;
Mid emphasizes vocals; Detail reduces bass masking; Air gently lifts upper treble.
They are listening starting points, not measured headphone correction or Dolby
Atmos rendering. They preserve the existing plugin family and end in a limiter.
Input gain is -3 to -3.75 dB; limiter input drive is +2 dB and ceiling -1 dB.
Original presets remain available. Select presets with the existing sidebar
picker or Super+I → Audio. The saved rollback choice for this deployment was
`codex-immersive`; live loaded-state readback is authoritative over stale rc files.

## Eden-only +12 dB

The control-center widget requires a double-click to enable; one click resets.
Super+I → Audio has a master switch that hides the widget and stops/cleans its
worker, plus a reset button. A separate systemd user service exists only while
boosting. It automatically ends when all armed Eden streams exit. No timer or
always-on audio-processing daemon is installed for the boost.

`eden-audio-boost` identifies the actual Eden executable and PID/start time,
using native PipeWire client metadata where stream metadata lacks a PID. App
names alone cannot impersonate Eden. It inserts a `linear` gain graph in the
Eden stream's own `audioconvert.filter-graph.777` slot. Other filter slots,
application volumes, routes, the system default sink and the current EasyEffects
preset remain unchanged. The gain therefore works with whichever effects are
currently selected; no saved-preset clone is required. This works with the host's
PipeWire 1.6.9 in-node filter API. Runtime readback must confirm the gain before
reporting active. It is not a separate surround/Atmos renderer.

+12 dB is approximately 3.98 times sample amplitude. The existing EasyEffects
limiter can reduce the resulting peaks; amplification does not recover clipped
source audio. Negative 12 dB would attenuate, so this is deliberately **+12 dB**.
The helper does not change volume persistently. Reset, ordinary stop, and
ExecStopPost recovery remove only this helper's graph from the same verified
stream identity. It preserves a gain changed externally rather than overwriting
it. An audio-server restart invalidates old stream identities. Kernel/API errors
are reported rather than showing a false active state.

Dependencies: Python 3, PipeWire 1.6 with audioconvert filter graphs, `pw-cli`,
`pw-dump`, `pactl`, systemd user services, EasyEffects and Quickshell. The widget
shows an error if Eden has no identifiable audio stream yet. To explicitly invoke
from CLI: `eden-audio-boost boost --confirmed`; reset with
`eden-audio-boost reset`. `disable` stops the worker and hides the widget.

Validation includes Qt mouse gesture tests (single-click cannot enable,
double-click enables, immediate reset/repeated clicks do not stack), executable
identity tests, silent live-stream reset/exit checks, and a +11.997 dB measured
isolated signal gain with return to baseline after reset. These are host DSP and
UI evidence; physical headset/gameplay listening remains the owner's assessment.
