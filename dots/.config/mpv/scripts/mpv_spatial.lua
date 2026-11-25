-- Explicit binaural surround & optional True Dolby HDMI passthrough for multichannel mpv only. Stereo and gains stay intact.
local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local home = os.getenv('HOME') or ''
local config_home = os.getenv('XDG_CONFIG_HOME') or (home .. '/.config')
local opt = {
    helper = home .. '/.local/bin/mpv-spatial',
    config = config_home .. '/mpv/spatial.json',
    legacy_guard = config_home .. '/mpv/spatial-legacy-off.conf',
}
options.read_options(opt, 'mpv_spatial')
local target = 'pipewire/effect_input.spatial-surround'
local channels_option = '7.1,5.1,stereo'
local spdif_codecs = 'eac3,ac3,truehd,dts,dts-hd'
local owned, passthrough_owned, busy, manual, queued = false, false, false, nil, false
local acquiring, acquire_failed, acquire_retries, sink_touched = false, false, 0, false
local pause_timer = nil
local previous_device, previous_channels, previous_spdif, own_socket
local legacy_safe = true
local ended = mp.get_property_native('eof-reached', false)

local function settings()
    local file = io.open(opt.config, 'r')
    if not file then return {enabled=false, automatic=true, passthrough=false, profile='atmos-7.1'} end
    local value = utils.parse_json(file:read('*a'));file:close()
    if type(value) ~= 'table' or type(value.enabled) ~= 'boolean' or type(value.automatic) ~= 'boolean' then
        return {enabled=false, automatic=true, passthrough=false, profile='atmos-7.1'}
    end
    return value
end

local function source_channels()
    for _, track in ipairs(mp.get_property_native('track-list', {})) do
        if track.type == 'audio' and track.selected and tonumber(track['demux-channel-count']) then
            return tonumber(track['demux-channel-count'])
        end
    end
    return mp.get_property_number('audio-params/channel-count', 0)
end

local function ready()
    for _, device in ipairs(mp.get_property_native('audio-device-list', {})) do
        if device.name == target then return true end
    end
    return false
end

local function is_hdmi_device(dev)
    if type(dev) ~= 'string' then return false end
    local lower = dev:lower()
    return lower:find('hdmi', 1, true) ~= nil or lower:find('iec958', 1, true) ~= nil or lower:find('spdif', 1, true) ~= nil
end

local function eld_has_dolby()
    if type(utils.readdir) ~= 'function' then return false end
    local ok, cards = pcall(utils.readdir, '/proc/asound', 'dirs')
    if not ok or type(cards) ~= 'table' then return false end
    for _, card in ipairs(cards) do
        if card:match('^card%d+$') then
            local ok2, files = pcall(utils.readdir, '/proc/asound/' .. card, 'files')
            if ok2 and type(files) == 'table' then
                for _, fname in ipairs(files) do
                    if fname:match('^eld#') then
                        local f = io.open('/proc/asound/' .. card .. '/' .. fname, 'r')
                        if f then
                            local text = f:read('*a') or ''
                            f:close()
                            if text:find('monitor_present%s+1') and text:find('eld_valid%s+1') then
                                local upper = text:upper()
                                if upper:find('E%-AC%-3') or upper:find('AC%-3') or upper:find('MLP') or upper:find('TRUEHD') or upper:find('DTS') then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function cancel_pause_timer()
    if pause_timer then
        if pause_timer.kill then pause_timer:kill() end
        pause_timer = nil
    end
end

local function publish(reason)
    local cfg = settings()
    local is_paused = mp.get_property_native('pause', false)
    mp.set_property_native('user-data/mpv-spatial', {
        enabled=cfg.enabled, automatic=cfg.automatic,
        profile=cfg.profile or 'atmos-7.1',
        passthrough=passthrough_owned and not is_paused,
        active=((owned and mp.get_property('audio-device') == target) or passthrough_owned) and not is_paused,
        source_channels=source_channels(), reason=reason,
        previous_device=previous_device, previous_channels=previous_channels,
        manual_override=manual,
    })
end

local function release_sink_async()
    if not sink_touched then return end
    sink_touched = false
    mp.command_native_async({name='subprocess', args={opt.helper, 'release'}, capture_stdout=true, capture_stderr=true}, function() end)
end

local function restore_passthrough()
    if passthrough_owned then
        passthrough_owned = false
        if mp.get_property('audio-spdif', '') == spdif_codecs then
            mp.set_property('audio-spdif', previous_spdif or '')
        end
        previous_spdif = nil
    end
end

local function restore(should_release)
    local was_owned = owned
    restore_passthrough()
    if owned then
        owned = false
        if mp.get_property('audio-device') == target then
            mp.set_property('audio-device', previous_device or 'auto')
        end
        if mp.get_property('options/audio-channels') == channels_option and previous_channels then
            mp.set_property('audio-channels', previous_channels)
        end
    end
    if should_release and (was_owned or sink_touched) then
        release_sink_async()
    end
end

local schedule

local function apply()
    queued = false
    if ended or mp.get_property_native('idle-active', false) then
        cancel_pause_timer();restore(true);publish('No active track');return
    end
    local cfg = settings()
    local count = source_channels()
    local current = mp.get_property('audio-device', 'auto')
    if owned and current ~= target then
        -- An explicit output change belongs to the user; do not route it back.
        restore(true);manual = false
    end
    local wanted = manual
    if wanted == nil then wanted = cfg.automatic end
    if not cfg.enabled or not legacy_safe or not wanted then
        cancel_pause_timer()
        restore(true)
        publish(not legacy_safe and 'Legacy profile could not be disabled' or 'Off')
        return
    end
    if count == 0 then publish('Waiting for audio');return end
    if count <= 2 then
        cancel_pause_timer();restore(true);publish('Stereo track — unchanged');return
    end
    if mp.get_property_native('pause', false) then
        if owned or sink_touched or passthrough_owned then
            if not pause_timer then
                pause_timer = mp.add_timeout(1.5, function()
                    pause_timer = nil
                    if mp.get_property_native('pause', false) then
                        restore(true)
                        publish('Paused — spatial sink released')
                    end
                end)
            end
        else
            publish('Paused — spatial sink released')
        end
        return
    end
    cancel_pause_timer()

    -- Optional True Dolby HDMI / S/PDIF bitstream passthrough: engage only on an explicit
    -- HDMI/S/PDIF route (never on analog headphones / EasyEffects / 2ch LPCM displays).
    local want_passthrough = cfg.passthrough == true and is_hdmi_device(current) and (cfg.hdmi_dolby == true or eld_has_dolby())
    if want_passthrough then
        if owned then
            owned = false
            if mp.get_property('options/audio-channels') == channels_option and previous_channels then
                mp.set_property('audio-channels', previous_channels)
            end
            release_sink_async()
        end
        if not passthrough_owned then
            previous_spdif = mp.get_property('audio-spdif', '')
            if mp.set_property('audio-spdif', spdif_codecs) then
                passthrough_owned = true
            end
        end
        publish('On — True Dolby HDMI bitstream passthrough')
        return
    else
        restore_passthrough()
    end

    if not ready() then
        if not owned and manual ~= true and current ~= 'auto' and current ~= 'pipewire/easyeffects_sink' and current ~= 'pulse/easyeffects_sink' then
            publish('Custom output preserved; press F8 to opt in');return
        end
        if owned then
            restore(false);publish('Spatial output unavailable');return
        end
        if acquiring then
            publish('Starting spatial output…');return
        end
        if acquire_failed then
            publish('Spatial output unavailable');return
        end
        acquiring = true
        sink_touched = true
        publish('Starting spatial output…')
        mp.command_native_async({name='subprocess', args={opt.helper, 'acquire'}, capture_stdout=true, capture_stderr=true}, function(success, result)
            acquiring = false
            if success and result and result.status == 0 then
                acquire_failed = false
                acquire_retries = 0
                schedule()
            else
                acquire_failed = true
                sink_touched = false
                publish('Spatial output unavailable')
                mp.msg.error(result and result.stderr or 'Spatial sink acquire failed')
            end
        end)
        return
    end
    if not owned then
        if manual ~= true and current ~= 'auto' and current ~= 'pipewire/easyeffects_sink' and current ~= 'pulse/easyeffects_sink' then
            publish('Custom output preserved; press F8 to opt in');return
        end
        previous_device = current
        previous_channels = mp.get_property('options/audio-channels', 'auto-safe')
        local ok = mp.set_property('audio-channels', channels_option)
        if not ok then publish('Could not select multichannel output');return end
        ok = mp.set_property('audio-device', target)
        if not ok then
            mp.set_property('audio-channels', previous_channels)
            publish('Could not select spatial output');return
        end
        owned = true
        sink_touched = true
    end
    local prof = cfg.profile == 'sofa-kemar' and 'SOFA 3D KEMAR' or 'Dolby Atmos 7.1 HRIR'
    publish('On — multichannel headphone surround (' .. prof .. ')')
end

schedule = function()
    if not queued then queued = true;mp.add_timeout(0, apply) end
end

local function show_state()
    local state = mp.get_property_native('user-data/mpv-spatial', {})
    mp.osd_message('Spatial audio: ' .. (state.reason or 'Off'), 2.5)
end

local function toggle()
    if busy then return end
    if source_channels() <= 2 then
        mp.osd_message('Spatial audio: stereo track stays stereo', 2.5);return
    end
    acquire_failed = false
    if settings().enabled then
        manual = not (owned or passthrough_owned);apply();show_state();return
    end
    busy = true
    mp.command_native_async({name='subprocess', args={opt.helper, 'enable'}, capture_stdout=true, capture_stderr=true}, function(success, result)
        busy = false
        if success and result.status == 0 then
            manual = true;apply();show_state()
        else
            mp.osd_message('Spatial audio could not start. Check Audio settings.', 3)
            mp.msg.error(result and result.stderr or 'Spatial helper failed')
        end
    end)
end

-- Retire the former automatic profile in an already-running player as well.
for _, profile in ipairs(mp.get_property_native('profile-list', {})) do
    if profile.name == 'spatial-multichannel' and profile['profile-cond'] ~= 'false' then
        if mp.get_property('audio-device') == target then
            mp.commandv('apply-profile', 'spatial-multichannel', 'restore')
        end
        local ok = mp.commandv('load-config-file', opt.legacy_guard)
        legacy_safe = ok ~= nil
        for _, updated in ipairs(mp.get_property_native('profile-list', {})) do
            if updated.name == 'spatial-multichannel' and updated['profile-cond'] ~= 'false' then legacy_safe = false end
        end
    end
end

mp.register_script_message('refresh', function(reason)
    if reason == 'automatic' or reason == 'enabled' or reason == 'profile' or reason == 'passthrough' then
        if reason == 'automatic' or reason == 'enabled' then
            manual = nil
        end
        acquire_failed = false
    elseif reason == 'release' then
        cancel_pause_timer()
        restore(false)
        publish('Paused — spatial sink released')
        return
    end
    apply()
end)
mp.add_forced_key_binding('F8', 'toggle', toggle)
for _, property in ipairs({'audio-params/channel-count', 'track-list', 'audio-device-list', 'audio-device', 'pause', 'idle-active'}) do
    mp.observe_property(property, 'native', schedule)
end
mp.register_event('file-loaded', function() ended = false;acquire_failed = false;schedule() end)
mp.register_event('end-file', function() ended = true;cancel_pause_timer();restore(true);publish('No active track') end)
mp.register_event('shutdown', function()
    cancel_pause_timer()
    if own_socket and mp.get_property('input-ipc-server') == own_socket then os.remove(own_socket) end
    if owned or sink_touched or mp.get_property('audio-device') == target then
        local pid = mp.get_property_number('pid')
        local args = {opt.helper, 'release'}
        if pid then
            args[#args+1] = '--exclude-pid'
            args[#args+1] = string.format('%d', pid)
        end
        if mp.command_native then
            mp.command_native({name='subprocess', args=args, detach=true})
        end
    end
end)

-- Keep Jukebox's IPC endpoint. Only standalone players without an IPC client
-- receive a private endpoint for live settings updates (avoids mpv's IPC-client bug).
if mp.get_property('input-ipc-server', '') == '' and mp.get_property('input-ipc-client', '') == '' then
    mp.command_native_async({name='subprocess', args={opt.helper, 'runtime'}, capture_stdout=true}, function(success, result)
        if success and result.status == 0 and mp.get_property('input-ipc-server', '') == '' then
            local directory = result.stdout:gsub('%s+$', '')
            if directory:sub(1, 1) == '/' then
                local path = directory .. '/' .. string.format('%d', mp.get_property_number('pid')) .. '.sock'
                if mp.set_property('input-ipc-server', path) then own_socket = path end
            end
        end
    end)
end
schedule()
