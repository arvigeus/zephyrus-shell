-- Set desktop identity before starting D-Bus services; no Plasma dependency.
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
hl.env("TERMINAL", os.getenv("TERMINAL") or "kitty")
-- KDE's standalone platform theme reads generated kdeglobals in both Qt 5 and
-- Qt 6. No Plasma session is needed; Qt also has a built-in KDE fallback.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("ZEPHYRUS_LOCK_WALLPAPER", config .. "/zephyrus-shell/lock-wallpaper")
