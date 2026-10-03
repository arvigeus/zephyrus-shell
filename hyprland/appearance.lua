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
    -- Route pointer/scroll input to the hovered window; keyboard focus changes
    -- only when it is clicked, including transitions between tiled/floating.
    input = { follow_mouse = 2, float_switch_override_focus = 0,
        touchpad = { natural_scroll = true, tap_to_click = true } },
    misc = { disable_hyprland_logo = true, force_default_wallpaper = 0,
        key_press_enables_dpms = true, mouse_move_enables_dpms = true },
    animations = { enabled = true },
})

-- Keep generated colors across compositor reloads, including a light palette.
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local generated = config .. "/zephyrus-shell/appearance.lua"
local theme = io.open(generated, "r")
if theme then
    theme:close()
    dofile(generated)
end
