local function rule(spec)
    return hl.window_rule(spec)
end

rule({ match = { class = "^()$", title = "^()$" }, no_blur = true })

rule({
    match = { class = "^(com\\.danklinux\\.dankcalendar)$" },
    float = true,
    center = true,
    size = { 1240, 860 },
})

-- for _, title in ipairs({ "Antigravity", "Manager", "Settings" }) do
--     rule({ match = { class = "^(antigravity)$", title = "^(" .. title .. ")$" }, float = true })
-- end

rule({ match = { class = "^(osu!)$" }, content = "game", idle_inhibit = "always" })
rule({ match = { class = "^(osu!\\.exe)$" }, immediate = true, content = "game", idle_inhibit = "always", no_vrr = true })
rule({ match = { class = "^(osu!\\.exe)$" }, fullscreen = true })
rule({ match = { tag = "tearing" }, immediate = true, no_vrr = true })
rule({ match = { class = "^(dev.eden_emu.eden|eden|Eden)$" }, content = "game", idle_inhibit = "always" })
-- rule({ match = { class = "^(google-chrome-unstable)$" }, immediate = true })

-- Preserve the inherited JetBrains transient-window focus workaround.
-- rule({
--     match = { class = "^jetbrains-.*$", float = true, title = "^$|^\\s$|^win\\d+$" },
--     no_initial_focus = true,
-- })

-- rule({ match = { class = "^(scrcpy)$" }, float = true, size = { 416, 896 }, center = true })
-- rule({ match = { title = "^(Mi_9T_Pro)$" }, float = true, size = { 400, 866 }, center = true })
-- rule({ match = { title = "^(S23_Ultra)$" }, float = true, size = { 400, 858 }, center = true })
-- rule({ match = { class = "^(org.kde.plasma-systemmonitor)$" }, float = true, size = { 1900, 900 }, center = true })
-- rule({ match = { class = "^(solaar)$" }, float = true, size = { 951, 569 }, center = true })
-- rule({ match = { class = "^(Windscribe)$" }, float = true, center = true, no_anim = true })
-- rule({ match = { class = "^(vmscope-float)$" }, float = true, size = { 980, 720 }, center = true })
