local directory = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
-- A single owned supervisor imports the environment and ends with this compositor.
hl.on("hyprland.start", function()
    hl.exec_cmd("python3 " .. quote(directory .. "../scripts/session.py"))
end)
