import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../core"

PopupWindow {
    id: root
    required property var barWindow
    required property string screenName
    property bool readyToOpen: true
    readonly property alias panel: content.item
    visible: ShellState.monitor === screenName && ShellState.panel === "clipboard" && readyToOpen
    anchor.window: barWindow
    anchor.rect.x: Math.max(0, barWindow.width - width - 14)
    anchor.rect.y: Theme.pillHeight + 6
    implicitWidth: Math.min(520, barWindow.width - 28)
    implicitHeight: Math.min(560, barWindow.screen.height - Theme.pillHeight - 24)
    color: "transparent"
    onWindowConnected: Qt.callLater(() => { if (visible) grab.active = true; })
    onVisibleChanged: { if (!visible) grab.active = false; }
    HyprlandFocusGrab {
        id: grab
        windows: [root, root.barWindow]
        onCleared: {
            if (ShellState.monitor === root.screenName && ShellState.panel === "clipboard") ShellState.dismissPanel();
        }
    }
    Loader {
        id: content
        anchors.fill: parent
        active: root.visible
        sourceComponent: ClipboardPanel { onCloseRequested: ShellState.dismissPanel() }
    }
}
