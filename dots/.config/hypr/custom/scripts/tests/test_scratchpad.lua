-- Run: lua ~/.config/hypr/custom/scripts/tests/test_scratchpad.lua
local calls, scratch, active = {}, nil, nil
hl = {
    get_active_window = function() return active end,
    get_workspace = function(name) assert(name == 'special:special'); return scratch end,
    dispatch = function(d) table.insert(calls, d) end,
    unbind = function() end, bind = function() end,
    dsp = {
        workspace = { move = function(opts) return {kind='workspace', opts=opts} end },
        window = { move = function(opts) return {kind='window', opts=opts} end },
    },
}
local module = dofile(os.getenv('HOME') .. '/.config/hypr/custom/scratchpad.lua')
local function window()
    return {workspace={name='6',visible=true}, monitor={id=1,name='HDMI-A-1'}, pinned=false}
end
local w = window()
scratch = {visible=false, monitor={id=0}, name='special:special'}
module.send(w)
assert(#calls == 2 and calls[1].kind == 'workspace')
-- Special workspace objects stringify to a negative relative selector in
-- this compositor; the literal name must be used to avoid moving another ws.
assert(calls[1].opts.workspace == 'special:special')
assert(calls[1].opts.monitor == 'HDMI-A-1')
assert(calls[2].opts.window == w and calls[2].opts.follow == false)
calls = {}; scratch.visible=true; module.send(w)
assert(#calls == 1 and calls[1].kind == 'window')
calls = {}; scratch.visible=false; scratch.monitor.id=1; module.send(w)
assert(#calls == 1)
calls = {}; scratch=nil; module.send(w); assert(#calls == 1)
for _,kind in ipairs({'pinned','hidden','already-special','no-monitor'}) do
    calls = {}; w=window()
    if kind=='pinned' then w.pinned=true
    elseif kind=='hidden' then w.workspace.visible=false
    elseif kind=='already-special' then w.workspace.name='special:special'
    else w.monitor=nil end
    module.send(w); assert(#calls == 0, kind)
end
calls = {}; active=nil; module.send(); assert(#calls == 0)
active=window(); module.send(); assert(#calls == 1)
print('PASS: hidden cross-monitor transfer, visible/same-monitor scratchpad, literal selector, stale focus and pinned guards')
