pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "windows"
import "WindowActivation.js" as WindowActivation

QtObject {
    id: root
    readonly property bool connected: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property var windows: order.windows
    property WindowOrderModel order: WindowOrderModel {
        toplevels: ToplevelManager.toplevels.values
        clients: Hyprland.toplevels.values
    }

    function clientFor(window) {
        return Hyprland.toplevels.values.find(client => client.wayland === window);
    }
    readonly property var monitors: Hyprland.monitors.values.filter(m => m.name !== "FALLBACK" && !m.lastIpcObject.disabled)
    readonly property var audioStreams: Pipewire.nodes.values.filter(node => node.isStream && node.isSink && !!node.audio)
    property PwObjectTracker streamTracker: PwObjectTracker { objects: root.audioStreams }

    function audioFor(window) {
        const client = clientFor(window);
        const pid = client ? Number(client.lastIpcObject.pid) : 0;
        // Use compositor/process identity, never a fuzzy title match. Application
        // IDs cover players whose audio is owned by a separate child process.
        return audioStreams.filter(node => {
            const props = node.properties;
            return (pid > 0 && Number(props["application.process.id"]) === pid)
                || (!!window.appId && props["application.id"] === window.appId);
        });
    }
    function toggleMuted(window) {
        const streams = audioFor(window);
        const mute = !streams.every(node => node.audio.muted);
        for (const node of streams) node.audio.muted = mute;
    }
    function activate(window) {
        if (!window || !windows.includes(window)) return;
        cancelActivation();
        ShellState.showDesktop();
        pendingActivation = {window: window, action: ""};
        activation.restart();
    }
    property var pendingActivation: null
    function cancelActivation() {
        pendingActivation = null;
        activation.stop();
        if (connected && Hyprland.usingLua)
            Hyprland.dispatch("function() " + WindowActivation.cancel(Quickshell.processId) + " end");
    }
    property Connections panelEvents: Connections {
        target: ShellState
        function onPanelChanged() { if (ShellState.panel) root.cancelActivation(); }
    }
    // Coalesce window-menu actions with activation; native Lua waits for the
    // compositor to commit the bar and module's exclusive-focus release.
    property Timer activation: Timer {
        interval: 50
        onTriggered: {
            const request = root.pendingActivation;
            root.pendingActivation = null;
            if (!request || !root.windows.includes(request.window)) return;
            const address = root.selector(request.window);
            if (root.connected && Hyprland.usingLua && address) {
                Hyprland.dispatch(WindowActivation.command(Quickshell.processId, address, request.action));
            } else request.window.activate();
            root.refresh.restart();
        }
    }
    function selector(window) {
        const client = clientFor(window);
        if (!client || !/^(0x)?[0-9a-f]+$/i.test(client.address)) return "";
        return JSON.stringify("address:0x" + client.address.replace(/^0x/i, ""));
    }
    function dispatchFor(window, action) {
        const address = selector(window);
        if (!connected || !Hyprland.usingLua || !address) return false;
        pendingActivation = {window: window, action: action};
        activation.restart();
        return true;
    }
    function toggleFloating(window) {
        activate(window);
        return dispatchFor(window, 'hl.dispatch(hl.dsp.window.float({window = w, action = "toggle"}))');
    }
    function moveToMonitor(window, name) {
        if (!monitors.some(m => m.name === name) || !/^[A-Za-z0-9_-]+$/.test(name)) return false;
        activate(window);
        return dispatchFor(window, 'hl.dispatch(hl.dsp.window.move({window = w, monitor = '
            + JSON.stringify(name) + ', follow = true}))');
    }
    function setWidth(window, fraction) {
        if (![0.25, 0.5, 0.75, 1].includes(fraction)) return false;
        const client = clientFor(window);
        const monitor = client ? monitors.find(m => m.id === client.lastIpcObject.monitor) : null;
        if (!monitor) return false;
        const info = monitor.lastIpcObject;
        const scale = info.scale || 1;
        const rotated = (info.transform || 0) % 2;
        const reserved = info.reserved || [0, 0, 0, 0];
        const width = Math.max(1, Math.round(((rotated ? info.height : info.width) / scale - reserved[0] - reserved[2]) * fraction));
        const height = Math.max(1, Math.round((rotated ? info.width : info.height) / scale - reserved[1] - reserved[3]));
        activate(window);
        return dispatchFor(window,
            'local active = hl.get_active_window(); if not active or active.address ~= w.address then return end; '
            + 'hl.dispatch(hl.dsp.window.fullscreen({window = w, action = "unset", layout_aware = false})); '
            + 'if not w.floating and w.workspace.tiled_layout == "scrolling" then '
            + 'hl.dispatch(hl.dsp.layout("colresize ' + fraction + '")); '
            + 'else hl.dispatch(hl.dsp.window.resize({window = w, x = ' + width + ', y = ' + height + ', relative = false})); '
            + 'if w.floating then hl.dispatch(hl.dsp.window.center({window = w})) end end');
    }
    function canDrag(window) {
        if (!connected || !Hyprland.usingLua) return false;
        const client = clientFor(window);
        return !!client && !!client.workspace && client.workspace.lastIpcObject.tiledLayout === "scrolling"
            && !!client.lastIpcObject.mapped && !client.lastIpcObject.floating && !client.lastIpcObject.hidden;
    }
    function canDrop(source, target) {
        if (source === target || !canDrag(source) || !canDrag(target)) return false;
        const a = clientFor(source).lastIpcObject;
        const b = clientFor(target).lastIpcObject;
        return a.monitor === b.monitor && a.workspace.id === b.workspace.id;
    }
    function reorder(source, target, after) {
        if (!canDrop(source, target)) return false;
        const a = clientFor(source).address;
        const b = clientFor(target).address;
        // Only compositor-provided hex addresses enter the Lua command.
        if (!/^(0x)?[0-9a-f]+$/i.test(a) || !/^(0x)?[0-9a-f]+$/i.test(b)) return false;
        const selector = address => JSON.stringify("address:0x" + address.replace(/^0x/i, ""));
        Hyprland.dispatch("function() zephyrus.reorder_column(" + selector(a) + ", " + selector(b)
            + ", " + (after ? "true" : "false") + ") end");
        refresh.restart();
        return true;
    }

    // Shared across all screen bars. Query after the compositor's layout animation
    // settles, because cached IPC geometry isn't updated with every layout change.
    property Timer refresh: Timer {
        interval: 220
        onTriggered: if (root.connected) Hyprland.refreshToplevels()
    }
    property Connections windowEvents: Connections {
        target: Hyprland
        enabled: root.connected
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "activewindowv2", "movewindow", "movewindowv2",
                 "changefloatingmode", "fullscreen", "workspacev2", "configreloaded",
                 "monitoraddedv2", "monitorremoved"].includes(event.name)) root.refresh.restart();
        }
    }
    // Dragging/resizing and some layout messages emit no window-order event.
    // One shared low-rate refresh catches these without starting shell workers.
    property Timer geometryUpdates: Timer {
        interval: 1000; repeat: true
        running: root.connected && ToplevelManager.toplevels.values.length > 1
        onTriggered: root.refresh.restart()
    }
    Component.onCompleted: {
        cancelActivation();
        if (connected) refresh.restart();
    }
}
