hl.bind("CTRL + SUPER + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"),
    { description = "User: Edit shell config" })
hl.bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
    { description = "User: Edit extra keybinds" })
hl.bind("SUPER + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"),
    { description = "User: Toggle keyboard layout" })

hl.bind("SUPER + F11", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/toggle-float.sh"),
    { description = "User: Toggle master float" })
hl.bind("SUPER + F12", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/exempt-float-size.py"),
    { description = "User: Exempt focused app from float sizing" })
hl.bind("SUPER + SHIFT + F12", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/exempt-float-size.py --title"))
hl.bind("SUPER + CTRL + F11", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/save-float-position-app.sh"),
    { description = "User: Save app float geometry" })
hl.bind("SUPER + CTRL + F12", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/save-float-position.sh"),
    { description = "User: Save window float geometry" })
hl.bind("SUPER + F10", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/geo-daemon.sh"),
    { description = "User: Toggle geometry restore" })
hl.bind("SUPER + F1", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/toggle-gpu-perf.sh"),
    { description = "User: Toggle AMD GPU power mode" })
hl.bind("SUPER + F2", hl.dsp.exec_cmd("~/.config/hypr/do.sh"))

-- Use Eden's native fullscreen path instead of forcing compositor fullscreen.
hl.unbind("SUPER + F")
hl.bind("SUPER + F", function()
    local window = hl.get_active_window()
    if window and (window.class == "dev.eden_emu.eden" or window.class == "eden") then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "b", window = window }))
        return
    end

    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
end, { description = "Window: Fullscreen (Eden native)" })

hl.bind("SUPER + ALT + A",
    hl.dsp.exec_cmd("pkill rofi; rofi -show animations -modi 'animations:~/.config/hypr/custom/scripts/hypr_anim.sh'"),
    { description = "User: Select animation profile" })

hl.bind("SUPER + Period", hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }))
hl.bind("SUPER + Comma", hl.dsp.window.set_prop({ prop = "no_blur", value = "toggle" }))

hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + Tab", hl.dsp.window.bring_to_top())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.bring_to_top())
hl.bind("ALT + Q", hl.dsp.focus({ last = true }))
hl.bind("ALT + Q", hl.dsp.window.bring_to_top())

local directions = {
    Left = { -30, 0 },
    Right = { 30, 0 },
    Up = { 0, -30 },
    Down = { 0, 30 },
}
for key, delta in pairs(directions) do
    hl.bind("SUPER + CTRL + " .. key,
        hl.dsp.window.move({ x = delta[1], y = delta[2], relative = true }), { repeating = true })
    hl.bind("SUPER + ALT + " .. key,
        hl.dsp.window.resize({ x = delta[1], y = delta[2], relative = true }), { repeating = true })
end
hl.bind("SUPER + ALT + C", hl.dsp.window.center())
hl.bind("SUPER + Z", hl.dsp.window.alter_zorder({ mode = "top" }))
hl.bind("SUPER + SHIFT + Z", hl.dsp.window.alter_zorder({ mode = "bottom" }))

hl.bind("CTRL + SUPER + M", hl.dsp.exec_cmd("kitty --class vmscope-float $HOME/.local/bin/vmscope watch"),
    { description = "User: VM sysctl scope" })
hl.bind("SUPER + F5", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/game-window.sh game"),
    { description = "Game: Toggle game mode on focused window" })
hl.bind("SUPER + F6", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/game-window.sh tear"),
    { description = "Game: Toggle tearing on focused window" })
hl.bind("SUPER + F7", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/game-window.sh status"),
    { description = "Game: Focused window VRR and tearing status" })
hl.bind("SUPER + SHIFT + F5", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/game-window.sh persist"),
    { description = "Game: Persist game mode for this app class" })

hl.bind("SUPER + F9", hl.dsp.exec_cmd("$HOME/.local/bin/obsctl toggle"),
    { description = "OBS: Start/stop recording", locked = true })
hl.bind("SUPER + SHIFT + F9", hl.dsp.exec_cmd("$HOME/.local/bin/obsctl pause"),
    { description = "OBS: Pause/resume recording", locked = true })
hl.bind("SUPER + ALT + F9", hl.dsp.exec_cmd("$HOME/.local/bin/obsctl split"),
    { description = "OBS: Split recording file", locked = true })
