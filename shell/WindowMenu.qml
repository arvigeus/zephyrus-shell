import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../core"
import "../widgets"

PopupWindow {
    id: root
    required property var barWindow
    property var targetWindow: null
    property alias panel: panel
    readonly property var client: targetWindow ? WindowList.clientFor(targetWindow) : null
    readonly property var streams: targetWindow ? WindowList.audioFor(targetWindow) : []
    readonly property bool muted: streams.length > 0 && streams.every(node => node.audio.muted)
    readonly property var otherMonitors: WindowList.monitors.filter(m => !client || m.id !== client.lastIpcObject.monitor)
    anchor.window: barWindow
    implicitWidth: 250
    implicitHeight: actions.implicitHeight + 20
    color: "transparent"
    visible: false
    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.visible = false }
    function openFor(window, button) {
        if (visible && targetWindow === window) { visible = false; return; }
        targetWindow = window;
        const point = button.mapToItem(barWindow.contentItem, 0, button.height);
        anchor.rect.x = Math.max(0, Math.min(barWindow.width - width, point.x));
        anchor.rect.y = point.y + 6;
        visible = true;
    }
    function perform(action) {
        const window = targetWindow;
        visible = false;
        if (window && WindowList.windows.includes(window)) action(window);
    }
    onWindowConnected: Qt.callLater(() => { if (visible) grab.active = true; })
    onVisibleChanged: {
        if (!visible) grab.active = false;
        else Qt.callLater(() => { if (visible) grab.active = true; });
    }
    HyprlandFocusGrab {
        id: grab
        windows: [root, root.barWindow]
        onCleared: root.visible = false
    }
    Connections {
        target: WindowList
        function onWindowsChanged() {
            if (root.targetWindow && !WindowList.windows.includes(root.targetWindow)) root.visible = false;
        }
    }
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Theme.surface; radius: Theme.radius; border.color: Theme.border
        ColumnLayout {
            id: actions
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 4
            Label {
                text: root.targetWindow ? root.targetWindow.title || root.targetWindow.appId : ""
                Layout.fillWidth: true; elide: Text.ElideRight
            }
            Action {
                visible: root.streams.length > 0
                text: root.muted ? "Unmute" : "Mute"; iconName: root.muted ? "volume-2" : "volume-x"
                Layout.fillWidth: true; textAlignment: Text.AlignLeft
                onClicked: root.perform(window => WindowList.toggleMuted(window))
            }
            Label { visible: !!root.client && WindowList.connected; text: "Size"; color: Theme.muted }
            RowLayout {
                visible: !!root.client && WindowList.connected && Hyprland.usingLua
                Layout.fillWidth: true
                Repeater {
                    model: [{label: "25%", value: 0.25}, {label: "50%", value: 0.5}, {label: "75%", value: 0.75}, {label: "Full", value: 1}]
                    Action {
                        required property var modelData
                        text: modelData.label; Layout.fillWidth: true; implicitWidth: 1
                        Accessible.description: modelData.label + " display width"
                        onClicked: root.perform(window => WindowList.setWidth(window, modelData.value))
                    }
                }
            }
            Action {
                visible: !!root.client && WindowList.connected && Hyprland.usingLua
                text: root.client && root.client.lastIpcObject.floating ? "Tile window" : "Float window"
                iconName: "panels-top-left"; Layout.fillWidth: true; textAlignment: Text.AlignLeft
                onClicked: root.perform(window => WindowList.toggleFloating(window))
            }
            Label { visible: WindowList.monitors.length > 1 && Hyprland.usingLua; text: "Monitor"; color: Theme.muted }
            Repeater {
                model: WindowList.monitors.length > 1 && Hyprland.usingLua ? root.otherMonitors : []
                Action {
                    required property var modelData
                    text: modelData.name; iconName: "monitor"; Layout.fillWidth: true; textAlignment: Text.AlignLeft
                    onClicked: root.perform(window => WindowList.moveToMonitor(window, modelData.name))
                }
            }
            Action {
                text: "Close"; iconName: "x"; destructive: true
                Layout.fillWidth: true; textAlignment: Text.AlignLeft
                onClicked: root.perform(window => window.close())
            }
        }
    }
}
