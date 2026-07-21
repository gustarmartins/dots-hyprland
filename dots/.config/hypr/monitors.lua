local monitors = {
    aoc = {
        output = "desc:AOC 27G2G4 0x00000A71",
        mode = "1920x1080@144.0",
        position = "0x0",
        scale = 1.0,
        vrr = 2,
    },
    aoc_recovery = {
        output = "DP-1",
        mode = "1920x1080@144.0",
        position = "0x0",
        scale = 1.0,
        bitdepth = 10,
        vrr = 2,
    },
    arzopa = {
        output = "desc:GWD ARZOPA 5=\\x9d\\x16%\\xf9`S0001",
        mode = "1920x1080@144.0",
        position = "1920x500",
        scale = 1.0,
        vrr = 0,
    },
}

hl.monitor(monitors.aoc)
hl.monitor(monitors.arzopa)

return monitors
