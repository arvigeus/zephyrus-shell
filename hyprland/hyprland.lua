-- Standalone config: Hyprland -c ~/Projects/zephyrus-shell/hyprland/hyprland.lua
local directory = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = directory .. "?.lua;" .. package.path
require("appearance")
require("windows")
require("bindings")
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("quickshell -n -p " .. string.format("%q", directory .. ".."))
end)
