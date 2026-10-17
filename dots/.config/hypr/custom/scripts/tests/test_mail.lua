-- Run: lua ~/.config/hypr/custom/scripts/tests/test_mail.lua
local calls, handlers, rules, windows, mail_ws, active, active_mon, active_ws = {}, {}, {}, {}, nil, nil, nil, nil
local now = 1000
os.time = function() return now end
os.difftime = function(t2, t1) return t2 - t1 end

hl = {
    get_windows = function() return windows end,
    get_active_window = function() return active end,
    get_active_monitor = function() return active_mon end,
    get_active_workspace = function(mon) assert(mon == active_mon); return active_ws end,
    get_workspace = function(name) assert(name == 'special:mail'); return mail_ws end,
    window_rule = function(spec)
        local r = { spec = spec, enabled = spec.enabled }
        function r:set_enabled(v) self.enabled = v end
        function r:is_enabled() return self.enabled end
        table.insert(rules, r)
        return r
    end,
    on = function(event, fn) handlers[event] = fn end,
    dispatch = function(d) table.insert(calls, d) end,
    dsp = {
        focus = function(opts) return { kind = 'focus', opts = opts } end,
        workspace = {
            move = function(opts) return { kind = 'workspace', opts = opts } end,
            toggle_special = function(name) return { kind = 'toggle_special', name = name } end,
        },
        window = {
            move = function(opts) return { kind = 'window', opts = opts } end,
        },
    },
}

local mail = dofile(os.getenv('HOME') .. '/.config/hypr/custom/mail.lua')
assert(#rules == 1 and rules[1].spec.workspace == 'special:mail silent' and rules[1].spec.no_initial_focus == true)
assert(rules[1]:is_enabled() == true, 'startup rule starts enabled when no Thunderbird window is open')

local function tb_window(ws_name, floating)
    return {
        address = '0x100',
        class = 'org.mozilla.Thunderbird',
        floating = floating or false,
        pinned = false,
        workspace = { id = -99, name = ws_name or 'special:mail', visible = ws_name ~= 'special:mail' },
        monitor = { id = 1, name = 'HDMI-A-1' },
    }
end

-- Background spawn disables startup rule so child dialogs open normally, and ignores initial urgent.
local main = tb_window('special:mail', false)
windows = { main }
handlers['window.open'](main)
assert(rules[1]:is_enabled() == false, 'startup rule disabled while Thunderbird window is open')

active_mon = { id = 1, name = 'HDMI-A-1' }
active_ws = { id = 2, name = '2', visible = true }
handlers['window.urgent'](main)
assert(#calls == 0, 'startup urgent within grace window must not steal focus')

-- Later app-launcher activation brings Thunderbird to the active workspace and focuses it.
now = 1005
handlers['window.urgent'](main)
assert(#calls == 2 and calls[1].kind == 'window' and calls[1].opts.workspace == '2' and calls[1].opts.follow == true)
assert(calls[2].kind == 'focus' and calls[2].opts.window == main)

-- SUPER + Q on main Thunderbird window hides it back to special:mail instead of closing.
calls = {}
main.workspace = { id = 2, name = '2', visible = true }
mail_ws = { visible = false, monitor = { id = 0, name = 'DP-1' }, name = 'special:mail' }
assert(mail.close_or_hide(main) == true)
assert(#calls == 2 and calls[1].kind == 'workspace' and calls[1].opts.workspace == 'special:mail' and calls[1].opts.monitor == 'HDMI-A-1')
assert(calls[2].kind == 'window' and calls[2].opts.workspace == 'special:mail' and calls[2].opts.follow == false)

-- Secondary floating dialog closes normally when main window is also open.
calls = {}
local dialog = tb_window('2', true)
dialog.address = '0x101'
windows = { main, dialog }
assert(mail.close_or_hide(dialog) == false)
assert(#calls == 0)

-- Last Thunderbird window closing re-enables the background startup rule.
windows = { main }
handlers['window.close'](main)
assert(rules[1]:is_enabled() == true, 'startup rule re-enabled after last Thunderbird window closes')

print('PASS: background startup rule, grace-window urgent guard, launcher activation, SUPER+Q hide-to-tray, dialog close, and rule re-arm')
