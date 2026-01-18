-- blast.lua — quick speed toggles for rapid-fire image slideshows
-- Place via: --script=mpv-scripts/blast.lua  (or in ~/.config/mpv/scripts)
local mp = require 'mp'

local function set_dur(sec)
  mp.set_property_native("image-display-duration", sec)
  mp.osd_message(string.format("image-display-duration = %.3fs", sec))
end

-- Alt+1-6 for duration presets
mp.add_forced_key_binding("Alt+1", "duration-very-fast", function() set_dur(0.001) end) -- Very fast (~1000 img/s)
mp.add_forced_key_binding("Alt+2", "duration-fast", function() set_dur(0.05) end) -- Fast (~20 img/s)
mp.add_forced_key_binding("Alt+3", "duration-medium", function() set_dur(0.1) end) -- Medium (~10 img/s)
mp.add_forced_key_binding("Alt+4", "duration-normal", function() set_dur(1.0) end) -- Normal (1 img/s)
mp.add_forced_key_binding("Alt+5", "duration-slow", function() set_dur(3.0) end) -- Slow (1 img/3s)
mp.add_forced_key_binding("Alt+6", "duration-very-slow", function() set_dur(5.0) end) -- Very slow (1 img/5s)

mp.add_forced_key_binding("c", "toggle-shuffle", function()
  local cur = mp.get_property_native("shuffle")
  mp.set_property_native("shuffle", not cur)
  mp.osd_message("shuffle = " .. tostring(not cur))
end)

mp.add_forced_key_binding("l", "toggle-loop", function()
  local cur = mp.get_property("loop-playlist")
  local newv = (cur == "inf") and "no" or "inf"
  mp.set_property("loop-playlist", newv)
  mp.osd_message("loop-playlist = " .. newv)
end)

-- Playlist navigation
mp.add_forced_key_binding("j", "playlist-prev", function()
  mp.command("playlist-prev")
end)

mp.add_forced_key_binding("k", "playlist-next", function()
  mp.command("playlist-next")
end)

-- Zoom controls
mp.add_forced_key_binding("Alt+KP_ADD", "zoom-in", function()
  mp.command("add video-zoom 0.1")
  local zoom = mp.get_property_number("video-zoom", 0)
  mp.osd_message(string.format("Zoom: %.1fx", 1 + zoom))
end)

mp.add_forced_key_binding("Alt+KP_SUBTRACT", "zoom-out", function()
  mp.command("add video-zoom -0.1")
  local zoom = mp.get_property_number("video-zoom", 0)
  mp.osd_message(string.format("Zoom: %.1fx", 1 + zoom))
end)

-- Also bind regular + and - keys
mp.add_forced_key_binding("Alt+=", "zoom-in-equals", function()
  mp.command("add video-zoom 0.1")
  local zoom = mp.get_property_number("video-zoom", 0)
  mp.osd_message(string.format("Zoom: %.1fx", 1 + zoom))
end)

mp.add_forced_key_binding("Alt+-", "zoom-out-hyphen", function()
  mp.command("add video-zoom -0.1")
  local zoom = mp.get_property_number("video-zoom", 0)
  mp.osd_message(string.format("Zoom: %.1fx", 1 + zoom))
end)

mp.add_forced_key_binding("Alt+BS", "zoom-reset", function()
  mp.command("set video-zoom 0")
  mp.command("set video-pan-x 0")
  mp.command("set video-pan-y 0")
  mp.osd_message("Zoom reset")
end)

-- Pan controls (arrow keys) - directions fixed
mp.add_forced_key_binding("Alt+LEFT", "pan-left", function()
  mp.command("add video-pan-x 0.05")
end)

mp.add_forced_key_binding("Alt+RIGHT", "pan-right", function()
  mp.command("add video-pan-x -0.05")
end)

mp.add_forced_key_binding("Alt+UP", "pan-up", function()
  mp.command("add video-pan-y 0.05")
end)

mp.add_forced_key_binding("Alt+DOWN", "pan-down", function()
  mp.command("add video-pan-y -0.05")
end)

-- Pan controls (WASD alternative) - directions fixed
mp.add_forced_key_binding("Alt+a", "pan-left-wasd", function()
  mp.command("add video-pan-x 0.05")
end)

mp.add_forced_key_binding("Alt+d", "pan-right-wasd", function()
  mp.command("add video-pan-x -0.05")
end)

mp.add_forced_key_binding("Alt+w", "pan-up-wasd", function()
  mp.command("add video-pan-y 0.05")
end)

mp.add_forced_key_binding("Alt+s", "pan-down-wasd", function()
  mp.command("add video-pan-y -0.05")
end)

-- Zoom level presets (1x, 2x, 3x)
mp.add_forced_key_binding("Alt+z", "zoom-1x", function()
  mp.command("set video-zoom 0")
  mp.command("set video-pan-x 0")
  mp.command("set video-pan-y 0")
  mp.osd_message("Zoom: 1x")
end)

mp.add_forced_key_binding("Alt+x", "zoom-2x", function()
  mp.command("set video-zoom 1.0")
  mp.command("set video-pan-x 0")
  mp.command("set video-pan-y 0")
  mp.osd_message("Zoom: 2x")
end)

mp.add_forced_key_binding("Alt+v", "zoom-3x", function()
  mp.command("set video-zoom 2.0")
  mp.command("set video-pan-x 0")
  mp.command("set video-pan-y 0")
  mp.osd_message("Zoom: 3x")
end)

-- Flag current image as "keep"
local function flag_keep()
  local path = mp.get_property("path")
  if not path then
    mp.osd_message("No file loaded")
    return
  end

  -- Get directory of current file
  local dir = path:match("(.*)/")
  if not dir then
    dir = "."
  end

  -- Write to keep.txt in the same directory
  local keep_file = dir .. "/keep.txt"
  local file = io.open(keep_file, "a")
  if file then
    file:write(path .. "\n")
    file:close()
    mp.osd_message("✓ Flagged as KEEP: " .. path:match("([^/]+)$"))
  else
    mp.osd_message("✗ Failed to write keep file")
  end
end

-- Bind 'm' for "mark/keep" (m is typically free in mpv)
mp.add_forced_key_binding("m", "flag-keep", flag_keep)

-- Move current image to trash
-- Try Shift+DEL for Shift+Delete combination
mp.add_forced_key_binding("Shift+DEL", "move-to-trash", function()
  local path = mp.get_property("path")
  if not path then
    mp.osd_message("No file loaded")
    return
  end

  -- Escape path for shell commands
  local escaped_path = path:gsub('"', '\\"')
  local filename = path:match("([^/]+)$")

  -- Try different methods to move to trash
  local success = false

  -- Method 1: Use osascript on macOS (properly escape the path)
  local osa_cmd = string.format('osascript -e "tell application \\"Finder\\" to move POSIX file \\"%s\\" to trash"', path)
  if os.execute(osa_cmd .. " 2>/dev/null") == 0 then
    success = true
  -- Method 2: Use mv to ~/.Trash (macOS/Linux)
  elseif os.execute('mv "' .. escaped_path .. '" ~/.Trash/ 2>/dev/null') == 0 then
    success = true
  -- Method 3: Use trash command if available
  elseif os.execute('trash "' .. escaped_path .. '" 2>/dev/null') == 0 then
    success = true
  end

  if success then
    mp.osd_message("🗑️  Moved to trash: " .. filename)
    -- Remove from playlist and move to next
    mp.command("playlist-remove current")
    mp.command("playlist-next")
  else
    mp.osd_message("✗ Failed to move to trash")
  end
end)
