-- Explicit binaural surround for multichannel mpv only. Stereo and gains stay intact.
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
local owned, busy, manual, queued = false, false, nil, false
local previous_device, previous_channels, own_socket
local legacy_safe = true
local ended = mp.get_property_native('eof-reached', false)

local function settings()
    local file = io.open(opt.config, 'r')
    if not file then return {enabled=false, automatic=true} end
    local value = utils.parse_json(file:read('*a'));file:close()
    if type(value) ~= 'table' or type(value.enabled) ~= 'boolean' or type(value.automatic) ~= 'boolean' then
        return {enabled=false, automatic=true}
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

local function publish(reason)
    local cfg = settings()
    mp.set_property_native('user-data/mpv-spatial', {
        enabled=cfg.enabled, automatic=cfg.automatic,
        active=owned and mp.get_property('audio-device') == target,
        source_channels=source_channels(), reason=reason,
        previous_device=previous_device, previous_channels=previous_channels,
        manual_override=manual,
    })
end

local function restore()
    if not owned then return end
    owned = false
    if mp.get_property('audio-device') == target then
        mp.set_property('audio-device', previous_device or 'auto')
    end
    if mp.get_property('options/audio-channels') == channels_option and previous_channels then
        mp.set_property('audio-channels', previous_channels)
    end
end

local function apply()
    queued = false
    if ended then restore();publish('No active track');return end
    local cfg = settings()
    local count = source_channels()
    local current = mp.get_property('audio-device', 'auto')
    if owned and current ~= target then
        -- An explicit output change belongs to the user; do not route it back.
        restore();manual = false
    end
    local wanted = manual
    if wanted == nil then wanted = cfg.automatic end
    if not cfg.enabled or not legacy_safe or not wanted then
        restore();publish(not legacy_safe and 'Legacy profile could not be disabled' or 'Off');return
    end
    if count == 0 then publish('Waiting for audio');return end
    if count <= 2 then restore();publish('Stereo track — unchanged');return end
    if not ready() then restore();publish('Spatial output unavailable');return end
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
    end
    publish('On — multichannel headphone surround')
end

local function schedule()
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
    if settings().enabled then
        manual = not owned;apply();show_state();return
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
    if reason == 'automatic' or reason == 'enabled' then manual = nil end
    apply()
end)
mp.add_forced_key_binding('F8', 'toggle', toggle)
for _, property in ipairs({'audio-params/channel-count', 'track-list', 'audio-device-list', 'audio-device'}) do
    mp.observe_property(property, 'native', schedule)
end
mp.register_event('file-loaded', function() ended = false;schedule() end)
mp.register_event('end-file', function() ended = true;restore();publish('No active track') end)
mp.register_event('shutdown', function()
    if own_socket and mp.get_property('input-ipc-server') == own_socket then os.remove(own_socket) end
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
