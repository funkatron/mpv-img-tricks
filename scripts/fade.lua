local opts = {
    duration = 0.3,
}
mp.options = require("mp.options")
mp.options.read_options(opts, "fade")

local anim_timer = nil
local fadeout_trigger = nil
local INTERVAL = 1 / 60

local function stop_anim()
    if anim_timer then
        anim_timer:kill()
        anim_timer = nil
    end
end

local function stop_fadeout_trigger()
    if fadeout_trigger then
        fadeout_trigger:kill()
        fadeout_trigger = nil
    end
end

local function fade_out()
    stop_anim()
    local brightness = 0
    local step = 100 * INTERVAL / opts.duration

    anim_timer = mp.add_periodic_timer(INTERVAL, function()
        brightness = brightness - step
        if brightness <= -100 then
            brightness = -100
            stop_anim()
        end
        mp.set_property_number("brightness", brightness)
    end)
end

local function schedule_fade_out()
    stop_fadeout_trigger()
    local display_dur = mp.get_property_number("image-display-duration", 0)
    if display_dur <= 0 then return end

    local delay = display_dur - opts.duration
    if delay < 0.1 then delay = 0.1 end

    fadeout_trigger = mp.add_timeout(delay, function()
        fade_out()
    end)
end

local function fade_in()
    stop_anim()
    stop_fadeout_trigger()
    local brightness = -100
    local step = 100 * INTERVAL / opts.duration

    mp.set_property_number("brightness", brightness)

    anim_timer = mp.add_periodic_timer(INTERVAL, function()
        brightness = brightness + step
        if brightness >= 0 then
            brightness = 0
            stop_anim()
            schedule_fade_out()
        end
        mp.set_property_number("brightness", brightness)
    end)
end

mp.register_event("file-loaded", function()
    fade_in()
end)

mp.add_hook("on_before_start_file", 50, function()
    mp.set_property_number("brightness", -100)
end)

mp.register_event("shutdown", function()
    stop_anim()
    stop_fadeout_trigger()
    mp.set_property_number("brightness", 0)
end)
