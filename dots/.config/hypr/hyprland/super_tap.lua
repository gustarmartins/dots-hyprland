-- Keep tap detection in the compositor. GlobalShortcut.onReleased also fires
-- after shortcuts, and a catchall bind does not observe already-bound keys.
local module = {}

function module.bind(on_tap)
    local down = {}
    local last_key = nil
    local candidate = nil

    -- Hyprland reports XKB keycodes before evaluating binds. Track the actual
    -- keys rather than assuming the physical location of either Super key.
    hl.on("input.keyboard.key", function(keycode, _, state)
        last_key = keycode
        if state == 1 then
            if not down[keycode] then
                candidate = nil
            end
            down[keycode] = true
        else
            down[keycode] = nil
        end
    end)

    local function arm()
        local first = next(down)
        if first and first == last_key and next(down, first) == nil then
            candidate = first
        end
    end

    local function release()
        local tapped = candidate ~= nil and candidate == last_key and next(down) == nil
        candidate = nil
        if tapped then
            on_tap()
        end
    end

    for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
        hl.bind("SUPER + " .. key, arm, { transparent = true, description = "Shell: Toggle search (tap only)" })
        hl.bind(key, release, { ignore_mods = true, transparent = true, release = true })
    end

    -- Observe buttons and wheel actions without consuming clicks, shadowing
    -- window drag/resize binds, or changing submaps.
    local function cancel()
        candidate = nil
    end
    for _, key in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275",
        "mouse:276", "mouse:277", "mouse:278", "mouse:279",
        "mouse_up", "mouse_down", "mouse_left", "mouse_right" }) do
        hl.bind(key, cancel, { ignore_mods = true, transparent = true,
            non_consuming = true, submap_universal = true })
    end
end

return module
