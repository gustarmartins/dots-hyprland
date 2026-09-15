hl.config({
    input = {
        kb_layout = "br,us",
        kb_options = "",
        accel_profile = "flat",
        sensitivity = 0.0,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    xwayland = {
        force_zero_scaling = true,
        create_abstract_socket = false,
    },
    misc = {
        focus_on_activate = false,
        middle_click_paste = false,
        animate_mouse_windowdragging = true,
        vrr = 1,
    },
    cursor = {
        no_break_fs_vrr = 1,
        min_refresh_rate = 48,
        inactive_timeout = 5.0,
    },
})

require("custom.animations.active.active")

hl.window_rule({
    name = "master_float",
    enabled = false,
    match = { class = ".*" },
    float = true,
})
hl.window_rule({
    name = "master_float_size",
    enabled = false,
    match = { class = "", title = "" },
    size = { 1366, 768 },
})
