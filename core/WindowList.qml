pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "windows"

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
    Component.onCompleted: if (connected) refresh.restart()
}
