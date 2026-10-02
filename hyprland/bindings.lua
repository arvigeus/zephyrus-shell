local root = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. ".."
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local shell = "quickshell -p " .. quote(root) .. " ipc call shell "
-- A modifier-only release bind can also fire after a Super chord on 0.56.
-- Track intervening keys so tapping Win opens Spaces without changing chords.
local pressedKeys, superUsed = {}, false
hl.on("input.keyboard.key", function(code, _, state)
    local isSuper = code == 133 or code == 134 -- XKB Left/Right Meta keycodes
    if state == 1 then
        if isSuper then
            if not pressedKeys[code] then superUsed = next(pressedKeys) ~= nil end
        elseif pressedKeys[133] or pressedKeys[134] then superUsed = true end
        pressedKeys[code] = true
    elseif state == 0 then pressedKeys[code] = nil end
end)
local function toggleSpaces()
    if not superUsed then hl.dispatch(hl.dsp.exec_cmd(shell .. "toggle left")) end
end
hl.bind("SUPER + SUPER_L", toggleSpaces, { release = true })
hl.bind("SUPER + SUPER_R", toggleSpaces, { release = true })
local function markSuperUsed() superUsed = true end
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("dolphin"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind("SUPER + M", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(shell .. "toggle left"))
hl.bind("SUPER + C", hl.dsp.exec_cmd(shell .. "toggle center"))
hl.bind("SUPER + COMMA", hl.dsp.exec_cmd(shell .. "toggle right"))
hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd(shell .. "openPlugin clipboard"))
local screenshot = "python3 " .. quote(root .. "/scripts/screenshot.py") .. " "
hl.bind("PRINT", hl.dsp.exec_cmd(screenshot .. "region"))
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd(screenshot .. "window"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd(screenshot .. "output"))
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd(shell .. "close"))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("SUPER + mouse:272", markSuperUsed, { non_consuming = true })
hl.bind("SUPER + mouse:273", markSuperUsed, { non_consuming = true })
-- Layout focus can scroll away from a maximized column on this monitor.
hl.bind("SUPER + LEFT", hl.dsp.layout("focus l"))
hl.bind("SUPER + RIGHT", hl.dsp.layout("focus r"))
hl.bind("SUPER + mouse_up", hl.dsp.layout("move -col"))
hl.bind("SUPER + mouse_down", hl.dsp.layout("move +col"))
hl.bind("SUPER + mouse_up", markSuperUsed, { non_consuming = true })
hl.bind("SUPER + mouse_down", markSuperUsed, { non_consuming = true })
for _, direction in ipairs({ "up", "down" }) do
    hl.bind("SUPER + " .. direction, hl.dsp.focus({ direction = direction }))
end
for i = 1, 9 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
