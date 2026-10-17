local M = {}

local MAIL_WORKSPACE = "special:mail"
local SILENT_WORKSPACE = "special:mail silent"
local CLASS_PATTERN = "^(org\\.mozilla\\.Thunderbird|[Tt]hunderbird)$"
local spawned_at = {}

function M.is_thunderbird(window)
    if not window then
        return false
    end
    local class = window.class or window.initial_class or ""
    return class == "org.mozilla.Thunderbird" or class == "thunderbird" or class == "Thunderbird"
end

function M.windows(exclude)
    local result = {}
    for _, w in ipairs(hl.get_windows() or {}) do
        if w ~= exclude and M.is_thunderbird(w) then
            table.insert(result, w)
        end
    end
    return result
end

local startup_rule = hl.window_rule({
    name = "thunderbird_background",
    enabled = #M.windows() == 0,
    match = { class = CLASS_PATTERN },
    workspace = SILENT_WORKSPACE,
    no_initial_focus = true,
})

function M.sync_startup_rule(exclude)
    if startup_rule and startup_rule.set_enabled then
        startup_rule:set_enabled(#M.windows(exclude) == 0)
    end
end

function M.hide(window)
    window = window or hl.get_active_window()
    if not M.is_thunderbird(window) or not window.workspace or not window.monitor or window.pinned then
        return false
    end
    if window.workspace.name == MAIL_WORKSPACE then
        if window.workspace.visible then
            hl.dispatch(hl.dsp.workspace.toggle_special("mail"))
            return true
        end
        return false
    end
    if not window.workspace.visible then
        return false
    end

    local mail_ws = hl.get_workspace(MAIL_WORKSPACE)
    if mail_ws and not mail_ws.visible and mail_ws.monitor
        and mail_ws.monitor.id ~= window.monitor.id then
        hl.dispatch(hl.dsp.workspace.move({ workspace = MAIL_WORKSPACE, monitor = window.monitor.name }))
    end
    hl.dispatch(hl.dsp.window.move({ window = window, workspace = MAIL_WORKSPACE, follow = false }))
    return true
end

function M.close_or_hide(window)
    window = window or hl.get_active_window()
    if not M.is_thunderbird(window) then
        return false
    end
    -- Secondary floating dialogs (e.g. Compose, OAuth, Account Settings) close
    -- normally while the main window remains open; the main/last window hides to tray.
    if window.floating and #M.windows() > 1 then
        return false
    end
    return M.hide(window)
end

function M.show(window)
    window = window or M.windows()[1]
    if not M.is_thunderbird(window) or not window.workspace then
        return false
    end
    local monitor = hl.get_active_monitor()
    local workspace = monitor and hl.get_active_workspace(monitor)
    if workspace and window.workspace.name ~= workspace.name then
        hl.dispatch(hl.dsp.window.move({ window = window, workspace = workspace.name, follow = true }))
    end
    hl.dispatch(hl.dsp.focus({ window = window }))
    return true
end

hl.on("window.open", function(w)
    if M.is_thunderbird(w) then
        if w.workspace and w.workspace.name == MAIL_WORKSPACE then
            spawned_at[w.address or w] = os.time()
        end
        M.sync_startup_rule()
    end
end)

local function on_removed(w)
    if M.is_thunderbird(w) then
        spawned_at[w.address or w] = nil
        M.sync_startup_rule(w)
    end
end

hl.on("window.close", on_removed)
hl.on("window.destroy", on_removed)

hl.on("window.urgent", function(w)
    if M.is_thunderbird(w) and w.workspace and w.workspace.name == MAIL_WORKSPACE then
        local opened = spawned_at[w.address or w]
        if opened and os.difftime(os.time(), opened) < 3 then
            return
        end
        M.show(w)
    end
end)

return M
