-- Pure policy fixture: no audio processes, sockets or desktop changes.
local source = assert(arg[1])
local cfg, props, handlers, queue, calls, toggler
local original_open = io.open
local function reset(enabled, count)
    cfg = {enabled=enabled, automatic=true}
    props = {['audio-device']='auto', ['options/audio-channels']='auto-safe',
        ['audio-params/channel-count']=count, ['audio-device-list']={{name='pipewire/effect_input.spatial-surround'}},
        ['track-list']={}, ['profile-list']={}, ['input-ipc-server']='/fixture/existing.sock',
        ['input-ipc-client']='', volume=73, pause=false}
    handlers, queue, calls = {}, {}, {}
    local mp = {}
    function mp.get_property(k,d) return props[k] == nil and d or props[k] end
    mp.get_property_native = mp.get_property;mp.get_property_number = mp.get_property
    function mp.set_property(k,v)
        calls[#calls+1]={k,v};props[k]=v
        if k=='audio-channels' then props['options/audio-channels']=v end
        return true
    end
    mp.set_property_native=mp.set_property
    function mp.add_timeout(_,fn) queue[#queue+1]=fn end
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
    function mp.command_native_async(_,fn) cfg.enabled=true;fn(true,{status=0,stdout=''}) end
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
local function start() dofile(source);drain() end
local target='pipewire/effect_input.spatial-surround'
local function untouched() assert(props.volume==73 and props.pause==false) end
local tests=0
local function test(name,fn) fn();untouched();tests=tests+1;print('PASS '..name)end
test('disabled keeps multichannel on its original output',function()reset(false,6);start();assert(props['audio-device']=='auto')end)
test('stereo remains stereo with master on',function()reset(true,2);start();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']=='auto')end)
test('automatic multichannel enters spatial route',function()reset(true,6);start();assert(props['audio-device']==target);assert(props['user-data/mpv-spatial'].active)end)
test('F8 off survives later track events',function()reset(true,6);start();toggler();assert(props['audio-device']=='auto');handlers['file-loaded']();drain();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']==target)end)
test('master off restores device and channel policy',function()reset(true,8);start();cfg.enabled=false;handlers.refresh('disabled');assert(props['audio-device']=='auto' and props['options/audio-channels']=='auto-safe')end)
test('external output change is not overwritten',function()reset(true,6);start();props['audio-device']='pipewire/owner-hdmi';handlers['audio-device']();drain();assert(props['audio-device']=='pipewire/owner-hdmi');assert(props['options/audio-channels']=='auto-safe')end)
test('custom initial route needs explicit opt in',function()reset(true,6);props['audio-device']='pipewire/owner-dac';start();assert(props['audio-device']=='pipewire/owner-dac');toggler();assert(props['audio-device']==target);toggler();assert(props['audio-device']=='pipewire/owner-dac')end)
test('missing spatial output restores normal route',function()reset(true,6);start();props['audio-device-list']={};handlers['audio-device-list']();drain();assert(props['audio-device']=='auto')end)
test('legacy automatic profile is disabled in a live player',function()reset(false,6);props['profile-list']={{name='spatial-multichannel',['profile-cond']='true'}};props['audio-device']=target;start();assert(props['profile-list'][1]['profile-cond']=='false' and props['audio-device']=='auto')end)
test('manual mode stays idle until F8',function()reset(true,6);cfg.automatic=false;start();assert(props['audio-device']=='auto');toggler();assert(props['audio-device']==target)end)
test('end of track stays restored after route notifications',function()reset(true,6);start();handlers['end-file']();handlers['audio-device']();drain();assert(props['audio-device']=='auto');handlers['file-loaded']();drain();assert(props['audio-device']==target)end)
io.open=original_open
print(tests..' policy checks passed')
