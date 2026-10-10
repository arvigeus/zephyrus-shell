hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- Personal monitor rules stay outside the checkout. Display settings restores
-- saved layouts itself from zephyrus-shell/display-profiles.json.
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local path = config .. "/zephyrus-shell/monitors.lua"
local file = io.open(path, "r")
if file then
    file:close()
    dofile(path)
end
