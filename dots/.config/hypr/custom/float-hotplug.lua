-- Hyprland 0.56.2 can return a workspace before the new monitor is arranged.
-- moveWorkspaceToMonitor translates its floats to the sentinel (-1,-1), then
-- CMonitor::moveTo skips translating them when initializing that origin.
-- Supply only that missing translation, once the real monitor layout exists.
-- No polling, position presets, focus changes, or generic window clamping.
local pending = {}
local timer_pending = false
local module = {}

local function eligible(w)
    return w and w.mapped and w.floating and not w.hidden and not w.pinned
        and w.fullscreen == 0 and w.fullscreen_client == 0
        and w.workspace and w.workspace.id > 0 and w.monitor
end

function module.reconcile()
    for address, saved in pairs(pending) do
        local w = hl.get_window("address:" .. address)
        if not eligible(w) or w.pid ~= saved.pid
            or w.workspace.id ~= saved.workspace or w.monitor.id ~= saved.monitor then
            pending[address] = nil
        elseif w.monitor.x ~= -1 or w.monitor.y ~= -1 then
            -- Native fixes, user moves, and intervening geometry policies win.
            -- Never apply a second translation to an already corrected window.
            pending[address] = nil
            if w.at.x == saved.x and w.at.y == saved.y
                and w.size.x == saved.width and w.size.y == saved.height then
                hl.dispatch(hl.dsp.window.move({
                    window = w,
                    x = saved.x + w.monitor.x + 1,
                    y = saved.y + w.monitor.y + 1,
                    relative = false,
                }))
            end
        end
    end
end

hl.on("workspace.move_to_monitor", function(workspace, monitor)
    for _, w in ipairs(hl.get_windows({ workspace = workspace })) do
        pending[w.address] = nil
        if eligible(w) and monitor.x == -1 and monitor.y == -1 then
            pending[w.address] = {
                pid = w.pid, workspace = workspace.id, monitor = monitor.id,
                x = w.at.x, y = w.at.y, width = w.size.x, height = w.size.y,
            }
        end
    end
    -- layout_changed normally handles this synchronously. One deferred pass
    -- also covers an arrangement completed before Lua receives its event.
    if next(pending) and not timer_pending then
        timer_pending = true
        hl.timer(function()
            timer_pending = false
            module.reconcile()
        end, { timeout = 100, type = "oneshot" })
    end
end)
hl.on("monitor.layout_changed", module.reconcile)
hl.on("window.close", function(w) pending[w.address] = nil end)

return module
