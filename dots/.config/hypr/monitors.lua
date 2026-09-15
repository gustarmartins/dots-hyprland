-- Native SDR desktop baseline, verified from EDID/DDC on 2026-09-09.
-- AOC 27G2: 8 bpc, RGB stripes, DP 1080p144, FreeSync 48-144 Hz.
-- ARZOPA: HDMI 1080p144 at 332.77 MHz; 10-bpc RGB would exceed its
-- advertised 360 MHz TMDS limit. Its advertised VRR is unusable in this lab.
local function profile(output, position, vrr)
    return {
        output = output,
        mode = "1920x1080@144.0",
        position = position,
        scale = 1.0,
        transform = 0,
        bitdepth = 8,
        cm = "srgb",
        vrr = vrr,
    }
end

local monitors = {
    aoc = profile("desc:AOC 27G2G4 0x00000A71", "0x0", 1),
    arzopa = profile("HDMI-A-1", "1920x500", 0),
}
-- Recovery uses the same values, changing only the selector.
monitors.aoc_recovery = {}
for key, value in pairs(monitors.aoc) do
    monitors.aoc_recovery[key] = value
end
monitors.aoc_recovery.output = "DP-1"
hl.monitor(monitors.aoc)
hl.monitor(monitors.arzopa)
return monitors
