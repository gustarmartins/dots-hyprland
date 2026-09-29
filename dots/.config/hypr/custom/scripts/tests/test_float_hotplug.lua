-- Unit checks for identity/race exclusions; real hotplug is tested separately.
local path = arg[1] or "dots/.config/hypr/custom/float-hotplug.lua"
local function fixture()
    local callbacks, moves, timers = {}, {}, {}
    local monitor = {id=1, x=-1, y=-1}
    local workspace = {id=6}
    local window = {address='0x1234',pid=42,mapped=true,floating=true,hidden=false,
        pinned=false,fullscreen=0,fullscreen_client=0,workspace=workspace,
        monitor=monitor,at={x=159,y=119},size={x=700,y=450}}
    hl = {
        on=function(event, fn) callbacks[event]=fn end,
        get_windows=function() return {window} end,
        get_window=function() return window end,
        timer=function(fn) table.insert(timers,fn) end,
        dsp={window={move=function(opts) return opts end}},
        dispatch=function(opts)
            table.insert(moves,opts)
            window.at={x=opts.x,y=opts.y}
        end,
    }
    local module=dofile(path)
    return window, monitor, callbacks, moves, timers, module
end
local w,m,events,moves,timers,module=fixture()
events['workspace.move_to_monitor'](w.workspace,m)
assert(#timers==1 and #moves==0)
m.x,m.y=1920,500
events['monitor.layout_changed']()
assert(#moves==1 and w.at.x==2080 and w.at.y==620)
module.reconcile(); timers[1]()
assert(#moves==1, 'Never translate twice')

for _,reason in ipairs({'moved','native_fix','resized','pid','workspace','monitor','closed'}) do
    w,m,events,moves,timers,module=fixture()
    events['workspace.move_to_monitor'](w.workspace,m)
    m.x,m.y=1920,500
    if reason=='moved' then w.at.x=300
    elseif reason=='native_fix' then w.at={x=2080,y=620}
    elseif reason=='resized' then w.size.x=800
    elseif reason=='pid' then w.pid=99
    elseif reason=='workspace' then w.workspace={id=7}
    elseif reason=='monitor' then w.monitor={id=3,x=0,y=0}
    elseif reason=='closed' then events['window.close'](w) end
    module.reconcile()
    assert(#moves==0,reason .. ' must be preserved')
end
for _,reason in ipairs({'tiled','unmapped','hidden','pinned','fullscreen','client_fullscreen','special','arranged'}) do
    w,m,events,moves,timers,module=fixture()
    if reason=='tiled' then w.floating=false
    elseif reason=='unmapped' then w.mapped=false
    elseif reason=='hidden' then w.hidden=true
    elseif reason=='pinned' then w.pinned=true
    elseif reason=='fullscreen' then w.fullscreen=2
    elseif reason=='client_fullscreen' then w.fullscreen_client=2
    elseif reason=='special' then w.workspace={id=-98}
    elseif reason=='arranged' then m.x,m.y=1920,500 end
    events['workspace.move_to_monitor'](w.workspace,m)
    m.x,m.y=1920,500; module.reconcile()
    assert(#moves==0 and #timers==0,reason .. ' must not be tracked')
end
print('PASS: exact translation, idempotence, user/native changes, identity and eligibility exclusions')
