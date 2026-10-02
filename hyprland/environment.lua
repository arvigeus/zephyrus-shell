-- Set desktop identity before starting D-Bus services; no Plasma dependency.
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
hl.env("TERMINAL", os.getenv("TERMINAL") or "kitty")
-- The installer supplies this config together with the native theme plugin.
-- Development checkouts continue to work before that package is installed.
local theme = io.open(config .. "/hypr/hyprqt6engine.conf", "r")
if theme then
    theme:close()
    hl.env("QT_QPA_PLATFORMTHEME", "hyprqt6engine")
end
hl.env("ZEPHYRUS_LOCK_WALLPAPER", config .. "/zephyrus-shell/lock-wallpaper")
