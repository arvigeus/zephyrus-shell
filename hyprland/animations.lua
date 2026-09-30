-- Hyprland speeds are in deciseconds; avoid inheriting its 800 ms default.
hl.curve("zephyrusQuick", { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })
hl.animation({ leaf = "global", enabled = true, speed = 1.5, bezier = "zephyrusQuick" })
hl.animation({ leaf = "windows", enabled = true, speed = 1.6, bezier = "zephyrusQuick" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.1, bezier = "zephyrusQuick" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.2, bezier = "zephyrusQuick" })
hl.animation({ leaf = "layers", enabled = true, speed = 1.2, bezier = "zephyrusQuick", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.6, bezier = "zephyrusQuick", style = "fade" })
