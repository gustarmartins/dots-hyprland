local M = {}

function M.send(window)
    window = window or hl.get_active_window()
    if not window or not window.workspace or not window.monitor or window.pinned then
        return
    end
    if window.workspace.name == "special:special" then
        return
    end
    -- Reject a stale focused window on an invisible workspace.
    if not window.workspace.visible then
        return
    end

    local scratchpad = hl.get_workspace("special:special")
    -- Like showing the scratchpad, sending to it follows the current monitor.
    -- Only relocate it while hidden; an already visible scratchpad stays put.
    -- Otherwise floating windows animate across global monitor coordinates
    -- while fading out, rather than disappearing in their original position.
    if scratchpad and not scratchpad.visible and scratchpad.monitor
        and scratchpad.monitor.id ~= window.monitor.id then
        hl.dispatch(hl.dsp.workspace.move({workspace = "special:special", monitor = window.monitor.name}))
    end
    hl.dispatch(hl.dsp.window.move({window = window, workspace = "special:special", follow = false}))
end

hl.unbind("SUPER + ALT + S")
hl.bind("SUPER + ALT + S", function() M.send() end,
    {description = "Window: Send to scratchpad"})

return M
