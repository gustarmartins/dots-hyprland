# 365 Ultra

`codex-365-ultra` is a dedicated listening preset for the original Charli xcx
**365**, developed against the local 24-bit/44.1 kHz stereo FLAC. It uses the
existing Stinger tuning as a starting point. It is not measured headphone
calibration or a Dolby Atmos renderer.

## What changed

The chain is **Equalizer → Mid-Side Equalizer → true-peak limiter**. Multiband
compression, bass harmonic enhancement and full-band widening are removed.
There is no artificial reverb, delay, exciter, crossfeed or automatic leveler.
The original quiet-to-heavy arrangement and existing stereo echoes provide the
contrast and spatial detail.

Common EQ input is -2.5 dB. The 12 bands at 45/100/160/250/400/630/1000/2000/
4000/5500/8000/12000 Hz use gains +0.75/+0.75/0/-2.2/-0.5/+0.25/+0.75/-0.75/
+1.25/-2.5/+0.75/+1.25 dB. These are taste adjustments, not an inverse acoustic
measurement of the headset.

Mid stays flat in the Mid-Side EQ. Side uses a +3.25 dB high shelf at 900 Hz
(Q 0.7), +0.75 dB bell at 3 kHz (Q 0.65), and -2.25 dB high shelf at 9 kHz
(Q 0.7). The final shelf keeps the very top from receiving the same lift as the
vocal/synth region. Limiter drive is +0.5 dB, threshold -1 dB, true-peak mode,
100% stereo link, with ALR and threshold gain-boost disabled. A final -0.85 dB
output gain supplies intersample headroom without changing dynamics or width.

## Native validation

The installed EasyEffects 8.3.0 rendered the exact presets on a separate private
PipeWire server without hardware access. Both stereo routes through every
intended plugin were inspected. A bypass calibration matched source amplitude
within 0.000002 dB. Render alignment removed transport/DSP delay before section
measurements. Probe excerpts were 20–30, 110–120, 170–180 and 190–200 seconds,
with one second of silence after each. Measurements exclude edge transients.

| Probe measure | Source | Detail Focus | 365 Ultra |
|---|---:|---:|---:|
| Bass rise, verse to climax (30–130 Hz) | 4.12 dB | 2.85 dB | 4.13 dB |
| Integrated probe loudness | -5.5 LUFS | -8.0 LUFS | -8.2 LUFS |
| 4× reconstructed true peak | +1.56 dBTP | -0.99 dBTP | about -1.84 dBTP |

The source peak is measured after conversion to the common 48 kHz test format;
it represents intersample headroom, not an assertion about clipped integer FLAC
samples. The new preset retained the source's measured bass rise while remaining
within 0.2 LUFS of the previous Detail Focus in this probe.

The complete 203.618-second song was also rendered natively. Its worst
intersample peak exposed headroom not seen in the excerpts. The final -0.85 dB
output stage was applied uniformly to that full render and independently
verified in a native probe render. The resulting 24-bit/48 kHz FLAC measures
-9.0 LUFS integrated and -1.1 dBTP with FFmpeg ebur128. It has the same duration
as the original within one sample. The original FLAC hash is unchanged.

A separate native tone test measured side-vs-mid gain +0.002 dB at 80 Hz,
+3.947 dB at 3 kHz and +1.944 dB at 10 kHz. Mono signals remained centered to
numerical precision. These tests verify processing, not physical listening or
vocal stem isolation.

## Use and rollback

Select `codex-365-ultra` in EasyEffects or the existing Quickshell preset picker.
The local deployment saved 323 live properties of the user's pre-change XCX
chain as `codex-365-before`, including unsaved changes. Original presets and the
source FLAC are retained. Local measured waveforms and reproduction scripts are
kept in `~/.local/state/easyeffects-365-ultra/`; they are not public song assets.

Listen through the original FLAC with this preset. Any separately rendered
listening copy is already processed and needs EasyEffects bypassed to avoid
applying the chain twice. Final physical/headset preference is the owner's
listening assessment.
