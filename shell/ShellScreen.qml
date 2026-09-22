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
        implicitHeight: 66
        exclusiveZone: 66
        color: "transparent"
        WlrLayershell.layer: leftDrawer.visible || rightDrawer.visible ? WlrLayer.Top : WlrLayer.Overlay
        WlrLayershell.namespace: "zephyrus-shell-bar"
        mask: Region {
            Region { item: left }
            Region { item: center }
            Region { item: right }
        }
        Row {
            id: left
            x: 14; y: 12; spacing: 8
            Action { text: "Desktop"; iconName: "monitor"; highlighted: root.selected && (ShellState.panel === "left" || ShellState.panel === "module"); onClicked: ShellState.toggle("left", root.screen.name) }
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
        visible: root.selected && !!ShellState.pluginId
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-module"
        WlrLayershell.keyboardFocus: visible && ShellState.panel === "module" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        ModuleLoader {
            anchors.fill: parent; active: root.selected && !!ShellState.pluginId
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
        screen: root.screen
        visible: root.selected && ShellState.panel === "center"
        anchors.top: true
        margins.top: 72
        implicitWidth: Math.min(850, root.screen.width - 28)
        implicitHeight: Math.min(root.screen.width < 728 ? 700 : 460, root.screen.height - 90)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "zephyrus-shell-attention"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Loader {
            anchors.fill: parent; active: parent.visible
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
