-- Default keyboard policy; optional user and session overrides follow below.
hl.config({ input = { kb_layout = "us,bg", kb_variant = ",phonetic",
    kb_options = "terminate:ctrl_alt_bksp,grp:alt_shift_toggle" } })
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local function load_if_present(path)
    local file = io.open(path, "r")
    if not file then return end
    file:close()
    dofile(path)
end
load_if_present(config .. "/zephyrus-shell/input-method.lua")
-- Keep the explicitly selected pair across compositor config reloads. Runtime
-- state is scoped to this compositor instance; a new login defaults to EN/BG.
local runtime = os.getenv("XDG_RUNTIME_DIR")
local instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
if runtime and instance then
    instance = instance:gsub("[^a-zA-Z0-9_.-]", "_")
    load_if_present(runtime .. "/zephyrus-shell/input-language-" .. instance .. ".lua")
end
