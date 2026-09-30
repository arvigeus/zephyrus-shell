hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- Personal monitor preferences stay outside the checkout. The entry point is
-- resolved here so a repository-linked development session picks up edits.
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local path = config .. "/zephyrus-shell/monitors.lua"
local file = io.open(path, "r")
if file then
    file:close()
    dofile(path)
end
-- Settings owns this atomic file; apply it after hand-written preferences.
local settings = config .. "/zephyrus-shell/display-settings.lua"
local saved = io.open(settings, "r")
if saved then
    saved:close()
    dofile(settings)
end
