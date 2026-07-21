hl.config({
    general = {
        col = {
            active_border   = "rgba(93909177)",
            inactive_border = "rgba(48464855)",
        },
    },
    misc = {
        background_color = "rgba(141314FF)",
    },
})

hl.window_rule({ -- not sure how to syntax "pin 1"
    match        = { pin = 1 },
    border_color = "rgba(d0c2d3AA) rgba(d0c2d377)",
})
