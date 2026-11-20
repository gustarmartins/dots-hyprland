local monitor_for_workspace = {}
for group = 0, 2 do
    local offset = group * 10
    for workspace = 1, 5 do
        hl.workspace_rule({ workspace = tostring(offset + workspace), monitor = "DP-1" })
        monitor_for_workspace[offset + workspace] = "DP-1"
    end
    for workspace = 6, 10 do
        hl.workspace_rule({ workspace = tostring(offset + workspace), monitor = "HDMI-A-1" })
        monitor_for_workspace[offset + workspace] = "HDMI-A-1"
    end
end

-- Safe mode can create workspace 2 on the second monitor before these rules
-- load. Rules govern placement but do not relocate existing workspaces on
-- config reload. Restore the same assignment after loading config or hotplug.
local restore_pending = false
local function restore_workspace_monitors()
    restore_pending = false
    local available = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.enabled and not monitor.is_mirror and (monitor.x ~= -1 or monitor.y ~= -1) then
            available[monitor.name] = true
        end
    end
    for _, workspace in ipairs(hl.get_workspaces()) do
        local target = monitor_for_workspace[workspace.id]
        if target and available[target] and workspace.monitor and workspace.monitor.name ~= target then
            hl.dispatch(hl.dsp.workspace.move({ workspace = workspace, monitor = target }))
        end
    end
end

local function schedule_restore()
    if restore_pending then return end
    restore_pending = true
    hl.timer(restore_workspace_monitors, { timeout = 100, type = "oneshot" })
end

hl.on("config.reloaded", schedule_restore)
hl.on("monitor.added", schedule_restore)
hl.on("monitor.layout_changed", schedule_restore)
