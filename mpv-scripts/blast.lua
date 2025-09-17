-- blast.lua — quick speed toggles for rapid-fire image slideshows
-- Place via: --script=mpv-scripts/blast.lua  (or in ~/.config/mpv/scripts)
local mp = require 'mp'

local function set_dur(sec)
  mp.set_property_native("image-display-duration", sec)
  mp.osd_message(string.format("image-display-duration = %.3fs", sec))
end

mp.add_key_binding("1", "blast-60fps", function() set_dur(0.016) end) -- ~60 img/s
mp.add_key_binding("2", "blast-20fps", function() set_dur(0.050) end) -- ~20 img/s
mp.add_key_binding("3", "blast-10fps", function() set_dur(0.100) end) -- ~10 img/s

mp.add_key_binding("c", "toggle-shuffle", function()
  local cur = mp.get_property_native("shuffle")
  mp.set_property_native("shuffle", not cur)
  mp.osd_message("shuffle = " .. tostring(not cur))
end)

mp.add_key_binding("l", "toggle-loop", function()
  local cur = mp.get_property("loop-playlist")
  local newv = (cur == "inf") and "no" or "inf"
  mp.set_property("loop-playlist", newv)
  mp.osd_message("loop-playlist = " .. newv)
end)
