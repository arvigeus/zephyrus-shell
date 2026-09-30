import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
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
        // Desktop panels sit below fullscreen apps. Raise the pills above an
        // open module, then lower them while the overlay drawers animate.
        WlrLayershell.layer: moduleWindow.visible && !leftDrawer.visible && !rightDrawer.visible
            ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-bar"
        // Hyprland restricts pointer input to exclusive-focus surfaces. Keep the
        // bar in that set alongside the module, whose hit region starts below it.
        WlrLayershell.keyboardFocus: root.screen.name === ShellState.pluginMonitor && (ShellState.panel === "module" || (root.selected && ShellState.panel === "center"))
            ? WlrKeyboardFocus.Exclusive
            : root.selected && ShellState.panel === "center" ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        Shortcut {
            sequence: "Escape"
            enabled: (root.screen.name === ShellState.pluginMonitor && ShellState.panel === "module") || (root.selected && ShellState.panel === "center")
            onActivated: {
                if (ShellState.panel === "center") {
                    if (attentionContent.item) attentionContent.item.dismiss();
                    else ShellState.dismissPanel();
                } else ShellState.close();
            }
        }
        mask: Region {
            Region { item: spaces }
            Region { item: runningApps }
            Region { item: center }
            Region { item: right }
            Region { item: tray }
        }
        IdleInhibitor { window: bar; enabled: KeepAwake.mode === "screen" && KeepAwake.active }
        Row {
            id: left
            x: 14; y: Theme.pillVerticalPadding; spacing: 8
            BarAction { id: spaces; text: "Spaces"; iconName: "grid-vertical"; showToolTip: false; highlighted: root.selected && ShellState.panel === "left"; onClicked: ShellState.toggle("left", root.screen.name) }
            RunningApps { id: runningApps; maximumWidth: Math.max(0, center.x - left.x - spaces.width - 2 * left.spacing); window: bar }
        }
        ClockPill {
            id: center
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.pillVerticalPadding
            highlighted: root.selected && ShellState.panel === "center"
            onClicked: ShellState.toggle("center", root.screen.name)
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14; y: Theme.pillVerticalPadding
            spacing: 8
            TrayPill { id: tray; window: bar; maximumWidth: Math.max(0, bar.width - 14 - right.width - center.x - center.width - 16) }
            StatusPill {
                id: right
                highlighted: root.selected && ShellState.panel === "right"
                onClicked: ShellState.toggle("right", root.screen.name)
            }
        }
    }
    PanelWindow {
        id: moduleWindow
        screen: root.screen
        visible: root.screen.name === ShellState.pluginMonitor && !!ShellState.pluginId
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-module"
        // Keep focus stable while the anchored popup is open. Reacquiring it
        // on dismissal can redirect the stationary pointer away from the bar.
        WlrLayershell.keyboardFocus: visible && (ShellState.panel === "module" || (root.selected && ShellState.panel === "center")) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // The backdrop still fills the screen; module input leaves the pills to the bar.
        mask: Region { x: 0; y: Theme.pillHeight; width: moduleWindow.width; height: Math.max(0, moduleWindow.height - y) }
        ModuleLoader {
            anchors.fill: parent
            screenName: root.screen.name
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
    PopupWindow {
        id: attentionWindow
        visible: root.selected && ShellState.panel === "center"
        anchor.window: bar
        anchor.rect.x: (bar.width - width) / 2
        anchor.rect.y: Theme.pillHeight + 6
        implicitWidth: Math.min(1240, root.screen.width - 28)
        implicitHeight: Math.min(root.screen.width < 900 ? 700 : 600, root.screen.height - Theme.pillHeight - 24)
        color: "transparent"
        // Wait for the popup surface before whitelisting it alongside the bar.
        onWindowConnected: Qt.callLater(() => { if (visible) attentionGrab.active = true; })
        onVisibleChanged: { if (!visible) attentionGrab.active = false; }
        HyprlandFocusGrab {
            id: attentionGrab
            windows: [attentionWindow, bar]
            onCleared: {
                if (root.selected && ShellState.panel === "center") ShellState.dismissPanel();
            }
        }
        Loader { id: attentionContent; anchors.fill: parent; active: parent.visible; sourceComponent: AttentionPanel {} }
    }
    PanelWindow {
        screen: root.screen
        visible: Attention.toast !== "" && ShellState.panel !== "center"
        anchors.top: true
        margins.top: Theme.pillHeight + 6
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
