local monitors = {
    aoc = {
        output = "desc:AOC 27G2G4 0x00000A71",
        -- Safe mode selected the display's preferred 1920x1080@60 mode and
        -- produced visibly sharper output than the forced 144 Hz mode.
        mode = "preferred",
        position = "0x0",
        scale = 1.0,
    },
    aoc_recovery = {
        output = "DP-1",
        mode = "1920x1080@144.0",
        position = "0x0",
        scale = 1.0,
        bitdepth = 10,
        vrr = 1,
    },
    arzopa = {
        output = "desc:GWD ARZOPA 5=\\x9d\\x16%\\xf9`S0001",
        mode = "preferred",
        position = "1920x516",
        scale = 1.0,
        vrr = 0,
    },
}

hl.monitor(monitors.aoc)
hl.monitor(monitors.arzopa)

return monitors
