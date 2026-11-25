-- Keep tap detection in the compositor. GlobalShortcut.onReleased also fires
-- after shortcuts, and a catchall bind does not observe already-bound keys.
local module = {}

local active_cancel = nil

function module.cancel()
    if active_cancel then
        active_cancel()
    end
end

local function snapshot_state()
    local win = hl.get_active_window()
    local mon = hl.get_active_monitor()
    local ws = mon and hl.get_active_workspace(mon) or nil
    local sp = mon and hl.get_active_special_workspace(mon) or nil
    return {
        win_addr = win and win.address or nil,
        win_x = win and win.at and win.at.x or nil,
        win_y = win and win.at and win.at.y or nil,
        win_w = win and win.size and win.size.x or nil,
        win_h = win and win.size and win.size.y or nil,
        win_float = win and win.floating or nil,
        win_fs = win and win.fullscreen or nil,
        ws_name = ws and (ws.addressable_name or ws.name) or nil,
        sp_name = sp and (sp.addressable_name or sp.name) or nil,
    }
end

local function state_changed(a, b)
    if not a or not b then
        return false
    end
    return a.win_addr ~= b.win_addr
        or a.win_x ~= b.win_x
        or a.win_y ~= b.win_y
        or a.win_w ~= b.win_w
        or a.win_h ~= b.win_h
        or a.win_float ~= b.win_float
        or a.win_fs ~= b.win_fs
        or a.ws_name ~= b.ws_name
        or a.sp_name ~= b.sp_name
end

function module.bind(on_tap)
    local down = {}
    local last_key = nil
    local candidate = nil
    local armed_snapshot = nil

    local function cancel()
        candidate = nil
        armed_snapshot = nil
    end
    active_cancel = cancel

    -- Hyprland reports XKB keycodes before evaluating binds. Track the actual
    -- keys rather than assuming the physical location of either Super key.
    hl.on("input.keyboard.key", function(keycode, _, state)
        last_key = keycode
        if state == 1 then
            if not down[keycode] then
                cancel()
            end
            down[keycode] = true
        else
            down[keycode] = nil
        end
    end)

    -- Cancel pending Super tap if a compositor action or trackpad gesture
    -- mutates workspace/window state while Super is held.
    for _, ev in ipairs({
        "window.move_to_workspace",
        "window.fullscreen",
        "window.close",
        "window.pin",
        "workspace.active",
        "workspace.special_active",
    }) do
        hl.on(ev, cancel)
    end

    local function arm()
        local first = next(down)
        if first and first == last_key and next(down, first) == nil then
            candidate = first
            armed_snapshot = snapshot_state()
        end
    end

    local function release()
        local snap = armed_snapshot
        local tapped = candidate ~= nil and candidate == last_key and next(down) == nil
        cancel()
        if tapped and not state_changed(snap, snapshot_state()) then
            on_tap()
        end
    end

    for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
        hl.bind("SUPER + " .. key, arm, { transparent = true, description = "Shell: Toggle search (tap only)" })
        hl.bind(key, release, { ignore_mods = true, transparent = true, release = true })
    end

    -- Observe buttons and wheel actions without consuming clicks, shadowing
    -- window drag/resize binds, or changing submaps.
    for _, key in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275",
        "mouse:276", "mouse:277", "mouse:278", "mouse:279",
        "mouse_up", "mouse_down", "mouse_left", "mouse_right" }) do
        hl.bind(key, cancel, { ignore_mods = true, transparent = true,
            non_consuming = true, submap_universal = true })
    end
end

return module
