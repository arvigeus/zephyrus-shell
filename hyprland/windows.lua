-- New windows float; Super+V opts individual windows into tiling.
hl.window_rule({ name = "floating-first", match = { class = ".*" }, float = true })
hl.window_rule({ name = "center-new-windows", match = { float = true }, center = true })
