-- Pure policy fixture: no audio processes, sockets or desktop changes.
local source = assert(arg[1])
local cfg, props, handlers, queue, timers, calls, async_calls, toggler
local original_open = io.open
local function reset(enabled, count)
    cfg = {enabled=enabled, automatic=true}
    props = {['audio-device']='auto', ['options/audio-channels']='auto-safe',
        ['audio-params/channel-count']=count, ['audio-device-list']={{name='pipewire/effect_input.spatial-surround'}},
        ['track-list']={}, ['profile-list']={}, ['input-ipc-server']='/fixture/existing.sock',
        ['input-ipc-client']='', volume=73, pause=false, ['idle-active']=false, pid=4242}
    handlers, queue, timers, calls, async_calls = {}, {}, {}, {}, {}
    local mp = {}
    function mp.get_property(k,d) return props[k] == nil and d or props[k] end
    mp.get_property_native = mp.get_property;mp.get_property_number = mp.get_property
    function mp.set_property(k,v)
        calls[#calls+1]={k,v};props[k]=v
        if k=='audio-channels' then props['options/audio-channels']=v end
        return true
    end
    mp.set_property_native=mp.set_property
    function mp.add_timeout(delay,fn)
        if delay == 0 then
            queue[#queue+1]=fn
            return {kill=function() end}
        end
        local handle = {fn=fn, killed=false}
        function handle:kill() self.killed = true end
        timers[#timers+1] = handle
        return handle
    end
    function mp.observe_property(k,_,fn) handlers[k]=fn end
    function mp.register_event(k,fn) handlers[k]=fn end
    function mp.register_script_message(k,fn) handlers[k]=fn end
    function mp.add_forced_key_binding(_,_,fn) toggler=fn end
    function mp.osd_message() end
    mp.msg={error=function() end}
    function mp.commandv(command)
        if command=='load-config-file' then props['profile-list'][1]['profile-cond']='false' end
        if command=='apply-profile' then props['audio-device']='auto';props['options/audio-channels']='auto-safe' end
        return true
    end
    function mp.command_native(spec)
        async_calls[#async_calls+1] = spec.args
        return {status=0, stdout=''}
    end
    function mp.command_native_async(spec,fn)
        async_calls[#async_calls+1] = spec.args
        local cmd = spec.args and spec.args[2]
        if cmd == 'enable' then cfg.enabled = true end
        if cmd == 'acquire' then
            props['audio-device-list']={{name='pipewire/effect_input.spatial-surround'}}
        end
        fn(true,{status=0,stdout=''})
    end
    package.loaded.mp=mp
    package.loaded['mp.utils']={parse_json=function()return cfg end}
    package.loaded['mp.options']={read_options=function()end}
    io.open=function(path,mode)
        if path:match('/mpv/spatial.json$') then return {read=function()return '{}' end,close=function()end} end
        return original_open(path,mode)
    end
end
local function drain()
    local rounds=0
    while #queue>0 do local q=queue;queue={};for _,fn in ipairs(q)do fn()end;rounds=rounds+1;assert(rounds<10)end
end
local function fire_timers()
    local t = timers; timers = {}
    for _, h in ipairs(t) do if not h.killed then h.fn() end end
    drain()
end
local function has_cmd(name)
    for _, args in ipairs(async_calls) do if args and args[2] == name then return true end end
    return false
end
local function start() dofile(source);drain() end
local target='pipewire/effect_input.spatial-surround'
local function untouched() assert(props.volume==73 and props.pause==false) end
local tests=0
local function test(name,fn) fn();untouched();tests=tests+1;print('PASS '..name)end
test('disabled keeps multichannel on its original output',function()reset(false,6);start();assert(props['audio-device']=='auto')end)
test('stereo remains stereo with master on',function()reset(true,2);start();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']=='auto')end)
test('automatic multichannel enters spatial route',function()reset(true,6);start();assert(props['audio-device']==target);assert(props['user-data/mpv-spatial'].active)end)
test('F8 off survives later track events',function()reset(true,6);start();toggler();assert(props['audio-device']=='auto');assert(has_cmd('release'));handlers['file-loaded']();drain();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']==target)end)
test('master off restores device and channel policy',function()reset(true,8);start();cfg.enabled=false;handlers.refresh('disabled');assert(props['audio-device']=='auto' and props['options/audio-channels']=='auto-safe')end)
test('external output change is not overwritten',function()reset(true,6);start();props['audio-device']='pipewire/owner-hdmi';handlers['audio-device']();drain();assert(props['audio-device']=='pipewire/owner-hdmi');assert(props['options/audio-channels']=='auto-safe')end)
test('custom initial route needs explicit opt in',function()reset(true,6);props['audio-device']='pipewire/owner-dac';start();assert(props['audio-device']=='pipewire/owner-dac');toggler();assert(props['audio-device']==target);toggler();assert(props['audio-device']=='pipewire/owner-dac')end)
test('missing spatial output restores normal route',function()reset(true,6);start();props['audio-device-list']={};handlers['audio-device-list']();drain();assert(props['audio-device']=='auto')end)
test('on-demand acquire starts spatial sink when absent',function()reset(true,6);props['audio-device-list']={};start();assert(has_cmd('acquire'));assert(props['audio-device']==target)end)
test('pause releases spatial route and sink, resume re-acquires cleanly',function()
    reset(true,6);start();assert(props['audio-device']==target)
    props.pause=true;handlers.pause();drain()
    fire_timers()
    assert(props['audio-device']=='auto' and props['options/audio-channels']=='auto-safe')
    assert(has_cmd('release'))
    props['audio-device-list']={};async_calls={}
    props.pause=false;handlers.pause();drain()
    assert(has_cmd('acquire'));assert(props['audio-device']==target)
end)
test('legacy automatic profile is disabled in a live player',function()reset(false,6);props['profile-list']={{name='spatial-multichannel',['profile-cond']='true'}};props['audio-device']=target;start();assert(props['profile-list'][1]['profile-cond']=='false' and props['audio-device']=='auto')end)
test('manual mode stays idle until F8',function()reset(true,6);cfg.automatic=false;start();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']==target)end)
test('end of track stays restored after route notifications',function()reset(true,6);start();handlers['end-file']();handlers['audio-device']();drain();assert(props['audio-device']=='auto');assert(has_cmd('release'));handlers['file-loaded']();drain();assert(props['audio-device']==target)end)
test('shutdown releases spatial sink with exclude-pid',function()reset(true,6);start();async_calls={};handlers.shutdown();assert(has_cmd('release'))end)
test('dolby hdmi passthrough engages only on hdmi with dolby eld and restores cleanly',function()
    reset(true,6);cfg.passthrough=true;cfg.hdmi_dolby=true
    props['audio-device']='pipewire/alsa_output.pci-0000_09_00.1.hdmi-stereo'
    props['audio-spdif']=''
    start()
    assert(props['audio-device']=='pipewire/alsa_output.pci-0000_09_00.1.hdmi-stereo')
    assert(props['audio-spdif']=='eac3,ac3,truehd,dts,dts-hd')
    assert(props['user-data/mpv-spatial'].passthrough==true)
    cfg.passthrough=false;handlers.refresh('passthrough')
    assert(props['audio-spdif']=='')
end)
test('dolby passthrough stays off on analog headphones even when enabled',function()
    reset(true,6);cfg.passthrough=true;cfg.hdmi_dolby=true
    props['audio-device']='pipewire/easyeffects_sink'
    props['audio-spdif']=''
    start()
    assert(props['audio-device']==target)
    assert(props['audio-spdif']=='')
end)
io.open=original_open
print(tests..' policy checks passed')
