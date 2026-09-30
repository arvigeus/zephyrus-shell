hl.config({
    general = {
        gaps_in = 6, gaps_out = 12, border_size = 2,
        resize_on_border = true,
        extend_border_grab_area = 8,
        col = { active_border = "rgba(ff465ccc)", inactive_border = "rgba(32353fff)" },
    },
    decoration = {
        rounding = 8,
        shadow = { enabled = true, range = 18, render_power = 3, color = "rgba(00000044)" },
        blur = { enabled = true, size = 4, passes = 2 },
    },
    -- Focusing a running-app button must leave the pointer on the pill bar.
    cursor = { no_warps = true },
    input = { follow_mouse = 0, touchpad = { natural_scroll = true, tap_to_click = true } },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0,
        key_press_enables_dpms = true, mouse_move_enables_dpms = true },
    animations = { enabled = true },
})
