-- Unified Hyprland + Quickshell Touchpad & Gesture Core
-- Portable across this laptop and future laptops: auto-detects any touchpad
-- via /proc/bus/input/devices while keeping external mice on flat accel.
--
-- IMPORTANT Hyprland 0.57.2 C++ pinch polarity note (TrackpadGestures.cpp:210):
--   e.scale < 1.0 (fingers pinching TOGETHER) -> direction = "pinchout"
--   e.scale > 1.0 (fingers spreading APART)   -> direction = "pinchin"
-- Semantic aliases below prevent anyone from having to remember this quirk.

local super_tap = require("hyprland.super_tap")
local scratchpad = require("custom.scratchpad")

local PINCH_TOGETHER = "pinchout" -- fingers closing together (scale < 1)
local SPREAD_APART   = "pinchin"  -- fingers spreading apart  (scale > 1)

--------------------------------------------------------------------------------
-- 1. Touchpad hardware auto-detection & per-device tuning
--------------------------------------------------------------------------------

local function normalize_hl_device_name(raw)
    -- Matches Hyprland's IHID::getHlName normalization: lowercase, spaces -> '-'
    return raw:lower():gsub("%s+", "-")
end

local function detect_touchpads()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then
        return {}
    end

    local found = {}
    local seen = {}
    local cur_name = nil
    local has_mouse_handler = false

    local function flush()
        if cur_name and has_mouse_handler then
            local lc = cur_name:lower()
            if lc:find("touchpad", 1, true)
                or lc:find("trackpad", 1, true)
                or lc:find("clickpad", 1, true)
                or lc:find("synaptics", 1, true) then
                local hl_name = normalize_hl_device_name(cur_name)
                if not seen[hl_name] then
                    seen[hl_name] = true
                    table.insert(found, hl_name)
                end
            end
        end
        cur_name = nil
        has_mouse_handler = false
    end

    for line in f:lines() do
        if line == "" then
            flush()
        else
            local name = line:match('^N:%s*Name="(.*)"%s*$')
            if name then
                cur_name = name
            elseif line:match("^H:%s*Handlers=.*mouse%d+") then
                has_mouse_handler = true
            end
        end
    end
    flush()
    f:close()
    return found
end

-- Global touchpad defaults & smooth gesture physics for laptop pads
hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            tap_to_click = true,
            tap_and_drag = true,
            drag_lock = 1, -- timeout drag lock: lift & continue drags across small pads
            scroll_factor = 0.7,
        },
    },
    general = {
        resize_on_border = true,
        extend_border_grab_area = 16,
        hover_icon_on_border = true,
    },
    gestures = {
        workspace_swipe_distance = 320,
        workspace_swipe_cancel_ratio = 0.25,
        workspace_swipe_min_speed_to_force = 12,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
        workspace_swipe_forever = true,
        close_max_timeout = 1000,
    },
})

-- Give every detected touchpad adaptive acceleration (fast cross-screen travel +
-- fine precision) without altering external desktop/gaming mice (accel_profile = flat).
for _, pad_name in ipairs(detect_touchpads()) do
    hl.device({
        name = pad_name,
        accel_profile = "adaptive",
        sensitivity = 0.15,
        natural_scroll = true,
        scroll_factor = 0.7,
        tap_to_click = true,
        tap_and_drag = true,
        drag_lock = 1,
        clickfinger_behavior = true,
        disable_while_typing = true,
    })
end

--------------------------------------------------------------------------------
-- 2. Compositor & Quickshell helpers
--------------------------------------------------------------------------------

local function has_layer(ns)
    local layers = hl.get_layers({ namespace = ns })
    return layers and layers[1] ~= nil
end

local function is_eglantine(win)
    if not win then return false end
    return win.class == "dev.eglantine.eglantine"
        or ((win.class == "Eglantine" or win.class == "eglantine")
            and win.title and win.title:match("^[Ee]glantine") ~= nil)
end

local function is_eden(win)
    if not win then return false end
    return win.class == "dev.eden_emu.eden" or win.class == "eden"
end

local function toggle_true_fullscreen(win)
    win = win or hl.get_active_window()
    if not win then return end
    if is_eglantine(win) then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "n", window = win }))
        return
    end
    if is_eden(win) then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "b", window = win }))
        return
    end
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = win }))
end

local function exit_fullscreen_or_maximize(win)
    win = win or hl.get_active_window()
    if not win or not win.fullscreen or win.fullscreen == 0 then
        return false
    end
    -- win.fullscreen bitmask: 1 = maximized, 2 = fullscreen, 3 = both
    if win.fullscreen == 2 and (is_eglantine(win) or is_eden(win)) then
        toggle_true_fullscreen(win)
        return true
    end
    if win.fullscreen == 1 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    else
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = win }))
        if win.fullscreen == 3 then
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
        end
    end
    return true
end

local function usable_monitor_area(mon)
    mon = mon or hl.get_active_monitor()
    if not mon or not mon.size then return nil end

    local scale = (mon.scale and mon.scale > 0) and mon.scale or 1.0
    local raw_w = mon.size.width / scale
    local raw_h = mon.size.height / scale
    -- Transform 1, 3, 5, 7 swap width and height (90° / 270° rotation).
    local rotated = mon.transform and (mon.transform % 2 == 1)
    local log_w = rotated and raw_h or raw_w
    local log_h = rotated and raw_w or raw_h

    local res = mon.reserved or {}
    local left   = res.left or 0
    local right  = res.right or 0
    local top    = res.top or 0
    local bottom = res.bottom or 0
    local gap    = 10

    local x = (mon.x or 0) + left + gap
    local y = (mon.y or 0) + top + gap
    local w = math.max(320, math.floor(log_w - left - right - gap * 2))
    local h = math.max(240, math.floor(log_h - top - bottom - gap * 2))
    return { x = math.floor(x), y = math.floor(y), w = w, h = h, gap = gap }
end

local function ensure_floating(win)
    if not win then return false end
    if win.fullscreen and win.fullscreen ~= 0 then
        exit_fullscreen_or_maximize(win)
    end
    if not win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "set", window = win }))
    end
    return true
end

local function place_floating(win, x, y, w, h)
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(w), y = math.floor(h), relative = false, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), relative = false, window = win }))
end

local function fit_floating_ratio(w_ratio, h_ratio)
    local win = hl.get_active_window()
    if not win then return end
    ensure_floating(win)
    local area = usable_monitor_area(win.monitor)
    if not area then
        hl.dispatch(hl.dsp.window.center({ window = win }))
        return
    end
    local w = math.floor(area.w * w_ratio)
    local h = math.floor(area.h * h_ratio)
    local x = area.x + math.floor((area.w - w) / 2)
    local y = area.y + math.floor((area.h - h) / 2)
    place_floating(win, x, y, w, h)
end

local function snap_or_split(side)
    local win = hl.get_active_window()
    if not win then return end
    if not win.floating then
        -- Tiled window: nudge split ratio cleanly.
        local delta = (side == "left") and "-0.12" or "+0.12"
        hl.dispatch(hl.dsp.layout("splitratio " .. delta))
        return
    end
    if win.fullscreen and win.fullscreen ~= 0 then
        exit_fullscreen_or_maximize(win)
    end
    local area = usable_monitor_area(win.monitor)
    if not area then return end
    local half_w = math.floor((area.w - area.gap) / 2)
    local x = (side == "left") and area.x or (area.x + half_w + area.gap)
    place_floating(win, x, area.y, half_w, area.h)
end

local function guard_super(fn)
    return function()
        super_tap.cancel()
        fn()
    end
end

--------------------------------------------------------------------------------
-- 3. LAYER 1 — 3 FINGERS (No Modifier): Everyday Navigation
--    Zero 3-finger pinch bound here -> impossible to misfire fullscreen!
--------------------------------------------------------------------------------

-- 3F Left / Right: 1:1 smooth workspace swipe (multi-workspace glide enabled)
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- 3F Up: Open Overview (idempotent — swiping up opens, never weirdly closes)
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        if has_layer("quickshell:sidebarLeft") then
            hl.dispatch(hl.dsp.global("quickshell:sidebarLeftClose"))
        end
        if has_layer("quickshell:sidebarRight") then
            hl.dispatch(hl.dsp.global("quickshell:sidebarRightClose"))
        end
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesOpen"))
    end,
})

-- 3F Down: Smart Back / Dismiss / Unfullscreen hierarchy
-- Always gets you cleanly out of Overview, panels, scratchpad, or fullscreen!
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function()
        if has_layer("quickshell:overview") then
            hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesClose"))
            return
        end
        if has_layer("quickshell:cheatsheet") then
            hl.dispatch(hl.dsp.global("quickshell:cheatsheetClose"))
            return
        end
        if has_layer("quickshell:mediaControls") then
            hl.dispatch(hl.dsp.global("quickshell:mediaControlsClose"))
            return
        end
        if has_layer("quickshell:sidebarLeft") or has_layer("quickshell:sidebarRight") then
            if has_layer("quickshell:sidebarLeft") then
                hl.dispatch(hl.dsp.global("quickshell:sidebarLeftClose"))
            end
            if has_layer("quickshell:sidebarRight") then
                hl.dispatch(hl.dsp.global("quickshell:sidebarRightClose"))
            end
            return
        end
        local mon = hl.get_active_monitor()
        if mon and hl.get_active_special_workspace(mon) then
            hl.dispatch(hl.dsp.workspace.toggle_special("special"))
            return
        end
        exit_fullscreen_or_maximize(hl.get_active_window())
    end,
})

--------------------------------------------------------------------------------
-- 4. LAYER 2 — 4 FINGERS (No Modifier): Quickshell Sheets, Scratchpad & Modes
--------------------------------------------------------------------------------

-- 4F Left: Close Left Sidebar if open, otherwise pull open Right Sidebar (Quick Toggles/Audio/Notifications)
hl.gesture({
    fingers = 4,
    direction = "left",
    action = function()
        if has_layer("quickshell:sidebarLeft") then
            hl.dispatch(hl.dsp.global("quickshell:sidebarLeftClose"))
        else
            hl.dispatch(hl.dsp.global("quickshell:sidebarRightOpen"))
        end
    end,
})

-- 4F Right: Close Right Sidebar if open, otherwise pull open Left Sidebar (AI/Translator)
hl.gesture({
    fingers = 4,
    direction = "right",
    action = function()
        if has_layer("quickshell:sidebarRight") then
            hl.dispatch(hl.dsp.global("quickshell:sidebarRightClose"))
        else
            hl.dispatch(hl.dsp.global("quickshell:sidebarLeftOpen"))
        end
    end,
})

-- 4F Down: 1:1 smooth slide-in / slide-out Scratchpad (special:special)
hl.gesture({
    fingers = 4,
    direction = "down",
    action = "special",
    workspace_name = "special",
})

-- 4F Up: Dismiss Scratchpad if open, otherwise toggle Media Controls popup
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        local mon = hl.get_active_monitor()
        if mon and hl.get_active_special_workspace(mon) then
            hl.dispatch(hl.dsp.workspace.toggle_special("special"))
            return
        end
        hl.dispatch(hl.dsp.global("quickshell:mediaControlsToggle"))
    end,
})

-- 4F Spread Apart (< >): Smart Expand (Normal -> Maximized w/ bar -> True Fullscreen)
hl.gesture({
    fingers = 4,
    direction = SPREAD_APART,
    action = function()
        local win = hl.get_active_window()
        if not win then return end
        local fs = win.fullscreen or 0
        if fs == 0 then
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = win }))
        elseif fs == 1 then
            toggle_true_fullscreen(win)
        end
    end,
})

-- 4F Pinch Together (> <): Smart Restore / Float-Tile
-- Fullscreen/Maximized -> back to normal; Normal -> toggle Float/Tile!
hl.gesture({
    fingers = 4,
    direction = PINCH_TOGETHER,
    action = function()
        local win = hl.get_active_window()
        if not win then return end
        if exit_fullscreen_or_maximize(win) then
            return
        end
        hl.dispatch(hl.dsp.window.float({ action = "toggle", window = win }))
    end,
})

--------------------------------------------------------------------------------
-- 5. LAYER 3 — SUPER + 3 FINGERS: Direct Window Physics (Desktop Parity!)
--------------------------------------------------------------------------------

-- SUPER + 3F Swipe (any direction): 1:1 move floating window / swap tiled window
hl.gesture({
    fingers = 3,
    mods = "SUPER",
    direction = "swipe",
    action = "move",
})

-- SUPER + 3F Pinch Together (> <): 1:1 animated Float
hl.gesture({
    fingers = 3,
    mods = "SUPER",
    direction = PINCH_TOGETHER,
    action = "float",
    mode = "float",
})

-- SUPER + 3F Spread Apart (< >): 1:1 animated Tile
hl.gesture({
    fingers = 3,
    mods = "SUPER",
    direction = SPREAD_APART,
    action = "float",
    mode = "tile",
})

-- SUPER + ALT + 3F Swipe (any direction): 1:1 live resize floating & tiled windows
hl.gesture({
    fingers = 3,
    mods = "SUPER + ALT",
    direction = "swipe",
    action = "resize",
})

-- SUPER + SHIFT + 3F Left / Right: Carry active window to Previous / Next workspace
hl.gesture({
    fingers = 3,
    mods = "SUPER + SHIFT",
    direction = "left",
    action = guard_super(function()
        hl.dispatch(hl.dsp.window.move({ workspace = "r-1", follow = true }))
    end),
})

hl.gesture({
    fingers = 3,
    mods = "SUPER + SHIFT",
    direction = "right",
    action = guard_super(function()
        hl.dispatch(hl.dsp.window.move({ workspace = "r+1", follow = true }))
    end),
})

-- SUPER + SHIFT + 3F Up: Center floating window (or float + fit + center if tiled)
hl.gesture({
    fingers = 3,
    mods = "SUPER + SHIFT",
    direction = "up",
    action = guard_super(function()
        local win = hl.get_active_window()
        if not win then return end
        if win.floating then
            hl.dispatch(hl.dsp.window.center({ window = win }))
        else
            fit_floating_ratio(0.76, 0.80)
        end
    end),
})

-- SUPER + SHIFT + 3F Down: Send active window to Scratchpad (multi-monitor safe)
hl.gesture({
    fingers = 3,
    mods = "SUPER + SHIFT",
    direction = "down",
    action = guard_super(function()
        scratchpad.send()
    end),
})

--------------------------------------------------------------------------------
-- 6. LAYER 4 — ADVANCED POWER GESTURES (Float Sizing, Zoom, Alt-Tab, Close, Media)
--------------------------------------------------------------------------------

-- SUPER + CTRL + 3F Left / Right: Snap floating half-screen | Adjust tiled split ratio
hl.gesture({
    fingers = 3,
    mods = "SUPER + CTRL",
    direction = "left",
    action = guard_super(function() snap_or_split("left") end),
})

hl.gesture({
    fingers = 3,
    mods = "SUPER + CTRL",
    direction = "right",
    action = guard_super(function() snap_or_split("right") end),
})

-- SUPER + CTRL + 3F Up: Comfortable Laptop Float Size (78% x 82%, centered)
hl.gesture({
    fingers = 3,
    mods = "SUPER + CTRL",
    direction = "up",
    action = guard_super(function() fit_floating_ratio(0.78, 0.82) end),
})

-- SUPER + CTRL + 3F Down: Compact Mini / PiP Float Size (48% x 54%, centered)
hl.gesture({
    fingers = 3,
    mods = "SUPER + CTRL",
    direction = "down",
    action = guard_super(function() fit_floating_ratio(0.48, 0.54) end),
})

-- SUPER + CTRL + 3F Pinch: 1:1 Live Cursor Magnifier Zoom (pinch closed resets to 1.0)
hl.gesture({
    fingers = 3,
    mods = "SUPER + CTRL",
    direction = "pinch",
    action = "cursor_zoom",
    zoom_level = "1.0",
    mode = "live",
})

-- ALT + 3F Left / Right: Touchpad Alt+Tab window cycling
hl.gesture({
    fingers = 3,
    mods = "ALT",
    direction = "left",
    action = function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end,
})

hl.gesture({
    fingers = 3,
    mods = "ALT",
    direction = "right",
    action = function()
        hl.dispatch(hl.dsp.window.cycle_next())
        hl.dispatch(hl.dsp.window.bring_to_top())
    end,
})

-- ALT + 3F Up: Pin / Unpin floating window across all workspaces (floats first if tiled)
hl.gesture({
    fingers = 3,
    mods = "ALT",
    direction = "up",
    action = function()
        local win = hl.get_active_window()
        if not win then return end
        if not win.floating then
            ensure_floating(win)
        end
        hl.dispatch(hl.dsp.window.pin({ action = "toggle", window = win }))
    end,
})

-- ALT + 3F Down: 1:1 Live Drag-to-Close Window (pull back < 20% to cancel!)
hl.gesture({
    fingers = 3,
    mods = "ALT",
    direction = "down",
    action = "close",
})

-- SUPER + 4F Up: Toggle Gestures Cheatsheet (opens straight to the Gestures tab!)
hl.gesture({
    fingers = 4,
    mods = "SUPER",
    direction = "up",
    action = guard_super(function()
        hl.dispatch(hl.dsp.global("quickshell:cheatsheetGesturesToggle"))
    end),
})

-- SUPER + 4F Down / Left / Right: Media Play-Pause / Prev / Next
hl.gesture({
    fingers = 4,
    mods = "SUPER",
    direction = "down",
    action = guard_super(function()
        hl.dispatch(hl.dsp.exec_cmd("playerctl play-pause"))
    end),
})

hl.gesture({
    fingers = 4,
    mods = "SUPER",
    direction = "left",
    action = guard_super(function()
        hl.dispatch(hl.dsp.exec_cmd("playerctl previous"))
    end),
})

hl.gesture({
    fingers = 4,
    mods = "SUPER",
    direction = "right",
    action = guard_super(function()
        hl.dispatch(hl.dsp.exec_cmd(
            "playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"
        ))
    end),
})
