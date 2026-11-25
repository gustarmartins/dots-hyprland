-- Event-driven per-monitor Kitty font sizing.
-- Delegates all file I/O and Kitty socket work off the compositor thread to
-- ~/.local/bin/kitty-font-monitor. No polling, no focus changes, and same-monitor
-- workspace switches do not spawn a helper (preserving manual per-window zoom).
local M = {}
local last_monitor = {}
local batch_timer = false

local function is_kitty(w)
    if not w then
        return false
    end
    local cls = w.class or w.initial_class or ""
    return cls == "kitty"
end

local function monitor_id_of(w, fallback_ws, fallback_mon)
    if fallback_mon and fallback_mon.id ~= nil then
        return fallback_mon.id
    end
    if w and w.monitor and w.monitor.id ~= nil then
        return w.monitor.id
    end
    if fallback_ws and fallback_ws.monitor and fallback_ws.monitor.id ~= nil then
        return fallback_ws.monitor.id
    end
    return nil
end

local function apply_pid(pid, wait_socket)
    if type(pid) ~= "number" or pid <= 0 then
        return
    end
    local flags = wait_socket and " --on-event --wait-socket" or " --on-event"
    hl.exec_cmd(string.format('"$HOME/.local/bin/kitty-font-monitor" apply --pid %d%s', pid, flags))
end

local function schedule_batch_apply()
    if batch_timer then
        return
    end
    batch_timer = true
    hl.timer(function()
        batch_timer = false
        hl.exec_cmd('"$HOME/.local/bin/kitty-font-monitor" apply --on-event')
    end, { timeout = 80, type = "oneshot" })
end

function M.sync_windows(windows, forced_monitor)
    local changed = false
    for _, w in ipairs(windows or {}) do
        if is_kitty(w) and w.address then
            local mid = monitor_id_of(w, w.workspace, forced_monitor)
            if mid ~= nil and last_monitor[w.address] ~= mid then
                last_monitor[w.address] = mid
                changed = true
            end
        end
    end
    if changed then
        schedule_batch_apply()
    end
end

-- Seed existing Kitty windows on load without altering their current zoom.
for _, w in ipairs(hl.get_windows() or {}) do
    if is_kitty(w) and w.address then
        local mid = monitor_id_of(w, w.workspace, nil)
        if mid ~= nil then
            last_monitor[w.address] = mid
        end
    end
end

hl.on("window.open", function(w)
    if not is_kitty(w) then
        return
    end
    local mid = monitor_id_of(w, w.workspace, nil)
    if w.address and mid ~= nil then
        last_monitor[w.address] = mid
    end
    apply_pid(w.pid, true)
end)

hl.on("window.move_to_workspace", function(w, ws)
    if not is_kitty(w) or not w.address then
        return
    end
    local mid = monitor_id_of(w, ws, nil)
    if mid ~= nil and last_monitor[w.address] ~= mid then
        last_monitor[w.address] = mid
        apply_pid(w.pid, false)
    end
end)

hl.on("workspace.move_to_monitor", function(ws, mon)
    if not ws or not mon then
        return
    end
    M.sync_windows(hl.get_windows({ workspace = ws }), mon)
end)

hl.on("monitor.layout_changed", function()
    M.sync_windows(hl.get_windows(), nil)
end)

local function forget(w)
    if w and w.address then
        last_monitor[w.address] = nil
    end
end

hl.on("window.close", forget)
hl.on("window.destroy", forget)

return M
