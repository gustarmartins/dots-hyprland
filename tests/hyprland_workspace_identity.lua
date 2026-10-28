-- Exercise the production Super+Q guard without closing real windows.
local path = arg[1] or 'dots/.config/hypr/custom/keybinds.lua'
local file = assert(io.open(path)); local source = file:read('*a'); file:close()
local start = assert(source:find('hl.bind("SUPER + Q", function()', 1, true))
local finish = assert(source:find('-- Use Eden', start, true))
local callback, window, regular, special
local closed, blocked = 0, 0
local env = {
    hl = {
        bind = function(_, fn) callback = fn end,
        get_active_monitor = function() return {} end,
        get_active_window = function() return window end,
        get_active_workspace = function() return regular end,
        get_active_special_workspace = function() return special end,
        notification = {create = function() blocked = blocked + 1 end},
        dsp = {window = {close = function() return 'close' end}},
        dispatch = function() closed = closed + 1 end,
    },
    mail = {close_or_hide = function() return false end},
}
assert(load(source:sub(start, finish - 1), 'close-guard', 't', env))()
regular = {id = 6}; window = {workspace = regular}; callback(); assert(closed == 1)
special = {addressable_name = 'special:visible'}
window = {workspace = special}; callback(); assert(closed == 2)
window = {workspace = {addressable_name = 'special:hidden'}}
callback(); assert(closed == 2 and blocked == 1, 'Nil IDs must not match hidden specials')
regular = {addressable_name = 'name:work'}; special = nil
window = {workspace = regular}; callback(); assert(closed == 3)
window = {workspace = {addressable_name = 'name:other'}}
callback(); assert(closed == 3 and blocked == 2)
window = nil; callback(); assert(closed == 3)
print('PASS: close guard preserves native named/special identity and rejects stale windows')
