local function rule(spec)
    return hl.window_rule(spec)
end

rule({ match = { class = "^()$", title = "^()$" }, no_blur = true })

for _, title in ipairs({ "Antigravity", "Manager", "Settings" }) do
    rule({ match = { class = "^(antigravity)$", title = "^(" .. title .. ")$" }, float = true })
end

rule({ match = { class = "^(osu!.exe)$" }, content = "game", immediate = true })
rule({ match = { class = "^(osu!)$" }, content = "game" })
rule({ match = { class = "^(dev.eden_emu.eden)$" }, content = "game" })
rule({ match = { class = "^(google-chrome-unstable)$" }, immediate = true })

-- Preserve the inherited JetBrains transient-window focus workaround.
rule({
    match = { class = "^jetbrains-.*$", float = true, title = "^$|^\\s$|^win\\d+$" },
    no_initial_focus = true,
})

rule({ match = { class = "^(scrcpy)$" }, float = true, size = { 416, 896 }, center = true })
rule({ match = { title = "^(Mi_9T_Pro)$" }, float = true, size = { 400, 866 }, center = true })
rule({ match = { title = "^(S23_Ultra)$" }, float = true, size = { 400, 858 }, center = true })
rule({ match = { class = "^(org.kde.plasma-systemmonitor)$" }, float = true, size = { 1900, 900 }, center = true })
rule({ match = { class = "^(solaar)$" }, float = true, size = { 951, 569 }, center = true })
rule({ match = { class = "^(Windscribe)$" }, float = true, center = true, no_anim = true })
rule({ match = { class = "^(vmscope-float)$" }, float = true, size = { 980, 720 }, center = true })

-- VRR is opt-in per window through the gamemode tag.
rule({ match = { class = ".*" }, no_vrr = true })
rule({ match = { tag = "gamemode" }, no_vrr = false, content = "game", idle_inhibit = "always" })
rule({ match = { tag = "tearing" }, immediate = true })

local function regex_escape(value)
    return (value:gsub("([^%w])", "\\%1"))
end

local game_classes_path = HOME .. "/.config/hypr/custom/game_classes.txt"
local game_classes = io.open(game_classes_path, "r")
if game_classes then
    for class in game_classes:lines() do
        if class ~= "" and not class:match("^%s*#") then
            rule({ match = { class = "^(" .. regex_escape(class) .. ")$" }, tag = "+gamemode" })
        end
    end
    game_classes:close()
end
