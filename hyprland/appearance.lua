hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.config({
    general = {
        gaps_in = 6, gaps_out = 12, border_size = 2,
        resize_on_border = true,
        col = { active_border = "rgba(9bd6c3ff)", inactive_border = "rgba(3b4848ff)" },
    },
    decoration = {
        rounding = 16,
        shadow = { enabled = true, range = 18, render_power = 3, color = "rgba(00000044)" },
        blur = { enabled = true, size = 4, passes = 2 },
    },
    input = { follow_mouse = 0, touchpad = { natural_scroll = true, tap_to_click = true } },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
    animations = { enabled = true },
})
