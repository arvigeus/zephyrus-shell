-- Native scrolling columns; dialogs retain Hyprland's floating heuristics.
hl.config({
    general = { layout = "scrolling" },
    scrolling = {
        column_width = 0.5,
        fullscreen_on_one_column = true,
        focus_fit_method = 1,
        follow_focus = true,
        direction = "right",
        wrap_focus = false,
    },
})
-- Super+V remains an escape hatch for a window that needs to float.
hl.window_rule({ name = "center-floating-windows", match = { float = true }, center = true })

-- Execute a drop atomically against current layout geometry, rather than relying
-- on the bar's cached positions. The list uses this through native Lua IPC.
zephyrus = zephyrus or {}
function zephyrus.reorder_column(sourceSelector, targetSelector, after)
    local source = hl.get_window(sourceSelector)
    local target = hl.get_window(targetSelector)
    if not source or not target or not source.mapped or not target.mapped
        or source.floating or target.floating or not source.workspace or not target.workspace
        or not source.monitor or not target.monitor
        or source.workspace.id ~= target.workspace.id or source.monitor.id ~= target.monitor.id
        or source.workspace.tiled_layout ~= "scrolling" then return end

    local columns, seen = {}, {}
    for _, window in ipairs(hl.get_workspace_windows(source.workspace)) do
        if window.mapped and not window.floating and not window.hidden then
            local x = window.at.x
            if not seen[x] then
                seen[x] = true
                table.insert(columns, x)
            end
        end
    end
    table.sort(columns)
    local from, to
    for index, x in ipairs(columns) do
        if x == source.at.x then from = index end
        if x == target.at.x then to = index end
    end
    if not from or not to or from == to then return end
    local destination = to + (after and 1 or 0) - (from < to and 1 or 0)
    local distance = destination - from
    if distance == 0 then return end

    hl.dispatch(hl.dsp.focus({window = source}))
    local active = hl.get_active_window()
    if not active or active.address ~= source.address then return end
    for _ = 1, math.abs(distance) do
        hl.dispatch(hl.dsp.layout(distance > 0 and "swapcol r" or "swapcol l"))
    end
end
