-- Standalone config: Hyprland -c /path/to/zephyrus-shell/hyprland/hyprland.lua
local directory = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
-- dofile avoids require's cache when a live session reloads its configuration.
for _, module in ipairs({ "environment", "monitors", "appearance", "input-method", "animations", "windows", "bindings", "session" }) do
    dofile(directory .. module .. ".lua")
end
