.pragma library

// Tokens are scoped to the shell process so a newer click or panel opening
// cancels an older compositor-side retry, including across QML reloads.
function cancel(owner) {
    const key = JSON.stringify(String(owner));
    return "zephyrus = zephyrus or {}; zephyrus.windowActivations = zephyrus.windowActivations or {}; "
        + "local requests = zephyrus.windowActivations; requests[" + key + "] = (requests[" + key + "] or 0) + 1; ";
}

function command(owner, selector, action) {
    const key = JSON.stringify(String(owner));
    return "function() " + cancel(owner)
        + "local token = requests[" + key + "]; local attempts = 0; "
        + "local function activate() "
        + "if requests[" + key + "] ~= token then return end; "
        + "local w = hl.get_window(" + selector + "); if not w or not w.mapped then return end; "
        // Native window focus is refused while any exclusive layer is mapped.
        // Check committed compositor state, rather than assuming a 50ms release.
        + "for _, layer in ipairs(hl.get_layers()) do "
        + "if layer.mapped and layer.interactivity == 1 then "
        + "attempts = attempts + 1; if attempts < 50 then "
        + "hl.timer(activate, {timeout = 20, type = 'oneshot'}) end; return end end; "
        + "hl.dispatch(hl.dsp.focus({window = w})); " + action
        + " end; activate() end";
}
