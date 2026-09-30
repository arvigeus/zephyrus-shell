import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../widgets"
import "../drawers"
import "../attention"

Scope {
    id: root
    required property var screen
    Component.onCompleted: {
        if (!ShellState.monitor && screen === Quickshell.screens[0]) ShellState.monitor = screen.name;
    }
    readonly property bool selected: ShellState.monitor === screen.name || (!Quickshell.screens.some(s => s.name === ShellState.monitor) && screen === Quickshell.screens[0])
    PanelWindow {
        screen: root.screen
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.background
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "zephyrus-shell-background"
        mask: Region {}
        Backdrop { anchors.fill: parent }
    }
    PanelWindow {
        id: bar
        screen: root.screen
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.pillHeight
        exclusiveZone: Theme.pillHeight
        color: "transparent"
        WlrLayershell.layer: leftDrawer.visible || rightDrawer.visible ? WlrLayer.Top : WlrLayer.Overlay
        WlrLayershell.namespace: "zephyrus-shell-bar"
        mask: Region {
            Region { item: left }
            Region { item: center }
            Region { item: right }
        }
        IdleInhibitor { window: bar; enabled: KeepAwake.mode === "screen" && KeepAwake.active }
        Row {
            id: left
            x: 14; y: 12; spacing: 8
            Action { text: "Spaces"; iconName: "grid-vertical"; highlighted: root.selected && ShellState.panel === "left"; onClicked: ShellState.toggle("left", root.screen.name) }
            RunningApps { maximumWidth: Math.max(0, bar.width / 2 - 260); window: bar }
        }
        Action {
            id: center
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            text: Qt.formatDateTime(clock.date, "ddd, MMM d   ·   HH:mm") + (Attention.count ? "   • " + Attention.count : "")
            highlighted: root.selected && ShellState.panel === "center"
            onClicked: ShellState.toggle("center", root.screen.name)
            SystemClock { id: clock; precision: SystemClock.Minutes }
        }
        StatusPill {
            id: right
            anchors.right: parent.right; anchors.rightMargin: 14; y: 12
            highlighted: root.selected && ShellState.panel === "right"
            onClicked: ShellState.toggle("right", root.screen.name)
        }
    }
    PanelWindow {
        screen: root.screen
        visible: root.screen.name === ShellState.pluginMonitor && !!ShellState.pluginId
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-module"
        WlrLayershell.keyboardFocus: visible && ShellState.panel === "module" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        ModuleLoader {
            anchors.fill: parent
            screenName: root.screen.name
            active: (root.screen.name === ShellState.pluginMonitor && !!ShellState.pluginId)
                || ShellState.runningPluginIds.some(id => ShellState.runningPluginMonitors[id] === root.screen.name)
            readyToLoad: !leftDrawer.visible && !rightDrawer.visible
        }
    }
    DrawerWindow {
        id: leftDrawer
        screen: root.screen
        side: "left"
        opened: root.selected && ShellState.panel === "left"
        contentSource: Qt.resolvedUrl("../drawers/LibraryDrawer.qml")
    }
    DrawerWindow {
        id: rightDrawer
        screen: root.screen
        side: "right"
        opened: root.selected && ShellState.panel === "right"
        contentSource: Qt.resolvedUrl("../drawers/ControlDrawer.qml")
    }
    PanelWindow {
        screen: root.screen
        visible: root.selected && ShellState.panel === "profile" && !leftDrawer.visible && !rightDrawer.visible
        implicitWidth: Math.min(380, root.screen.width - 32); implicitHeight: 320
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zephyrus-shell-profile"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Loader { anchors.fill: parent; active: parent.visible; sourceComponent: UserProfilePanel {} }
    }
    PanelWindow {
        id: attentionWindow
        screen: root.screen
        visible: root.selected && ShellState.panel === "center"
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property real popupWidth: Math.min(1240, width - 28)
        readonly property real popupHeight: Math.min(width < 900 ? 700 : 600, height - 90)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zephyrus-shell-attention"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region {
            Region { item: attentionAbove }
            Region { item: attentionLeft }
            Region { item: attentionRight }
            Region { item: attentionBelow }
            Region { item: attentionPopup }
        }
        MouseArea {
            id: attentionAbove
            x: 0; y: Theme.pillHeight; width: parent.width; height: Math.max(0, attentionPopup.y - y)
            acceptedButtons: Qt.AllButtons
            onClicked: ShellState.dismissPanel()
        }
        MouseArea {
            id: attentionLeft
            x: 0; y: attentionPopup.y; width: attentionPopup.x; height: attentionPopup.height
            acceptedButtons: Qt.AllButtons
            onClicked: ShellState.dismissPanel()
        }
        MouseArea {
            id: attentionRight
            x: attentionPopup.x + attentionPopup.width; y: attentionPopup.y
            width: parent.width - x; height: attentionPopup.height
            acceptedButtons: Qt.AllButtons
            onClicked: ShellState.dismissPanel()
        }
        MouseArea {
            id: attentionBelow
            x: 0; y: attentionPopup.y + attentionPopup.height
            width: parent.width; height: parent.height - y
            acceptedButtons: Qt.AllButtons
            onClicked: ShellState.dismissPanel()
        }
        Loader {
            id: attentionPopup
            x: (parent.width - width) / 2; y: 72
            width: attentionWindow.popupWidth; height: attentionWindow.popupHeight
            active: parent.visible
            sourceComponent: AttentionPanel {}
        }
    }
    PanelWindow {
        screen: root.screen
        visible: Attention.toast !== "" && ShellState.panel !== "center"
        anchors.top: true
        margins.top: 72
        implicitWidth: 360; implicitHeight: 64
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "zephyrus-shell-toast"
        Action {
            anchors.fill: parent
            text: Attention.toast
            onClicked: { Attention.toast = ""; ShellState.toggle("center", root.screen.name); }
        }
    }
}
