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
-- Legacy Settings rules are migrated by the shell using physical monitor
-- identities. Once migrated, only the connected setup chooses layout/enabled
-- state; replaying connector rules here could configure a different USB-C display.
local settings = config .. "/zephyrus-shell/display-settings.lua"
local saved = io.open(settings, "r")
if saved then
    saved:close()
    local profiles = io.open(config .. "/zephyrus-shell/display-profiles.json", "r")
    if profiles then
        profiles:close()
    else
        dofile(settings)
    end
end
