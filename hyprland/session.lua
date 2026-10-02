-- UWSM imports the compositor environment and owns graphical-session.target.
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize HYPRLAND_INSTANCE_SIGNATURE ZEPHYRUS_LOCK_WALLPAPER QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME TERMINAL")
end)
