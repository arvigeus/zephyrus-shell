import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../widgets"
import "../drawers"
import "../attention"
import "../clipboard"

Scope {
    id: root
    required property var screen
    readonly property string screenName: screen ? screen.name : ""
    readonly property real screenWidth: screen ? screen.width : 0
    readonly property real screenHeight: screen ? screen.height : 0
    property var sharedModules: null
    function syncModuleSurface() {
        if (!sharedModules || !screen || screenName !== ShellState.pluginMonitor) return;
        sharedModules.parent = moduleWindow.contentItem;
        sharedModules.readyToLoad = !leftDrawer.visible && !rightDrawer.visible;
    }
    Component.onCompleted: {
        if (!ShellState.monitor && screen && screen === Quickshell.screens[0]) ShellState.monitor = screenName;
        syncModuleSurface();
    }
    Component.onDestruction: {
        if (sharedModules && sharedModules.parent === moduleWindow.contentItem) sharedModules.parent = null;
    }
    Connections {
        target: ShellState
        function onPluginMonitorChanged() { root.syncModuleSurface(); }
        function onPanelChanged() { Qt.callLater(root.syncModuleSurface); }
    }
    readonly property bool selected: !!screen && (ShellState.monitor === screenName || (!Quickshell.screens.some(s => s.name === ShellState.monitor) && screen === Quickshell.screens[0]))
    readonly property bool popupOpen: root.selected && ["center", "clipboard"].includes(ShellState.panel)
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
        WlrLayershell.keyboardFocus: root.screenName === ShellState.pluginMonitor && (ShellState.panel === "module" || root.popupOpen)
            ? WlrKeyboardFocus.Exclusive
            : root.popupOpen ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        Shortcut {
            sequence: "Escape"
            enabled: (root.screenName === ShellState.pluginMonitor && ShellState.panel === "module") || root.popupOpen
            onActivated: {
                if (ShellState.panel === "center") {
                    if (attentionContent.item) attentionContent.item.dismiss();
                    else ShellState.dismissPanel();
                } else if (ShellState.panel === "clipboard") ShellState.dismissPanel();
                else ShellState.close();
            }
        }
        mask: Region {
            Region { item: spaces }
            Region { item: runningApps }
            Region { item: center }
            // Track the anchored row itself so newly added controls keep their
            // hit region when the row moves as tray/status widths change.
            Region { item: rightPills }
        }
        IdleInhibitor { window: bar; enabled: KeepAwake.mode === "screen" && KeepAwake.active }
        Row {
            id: left
            x: 14; y: Theme.pillVerticalPadding; spacing: 8
            BarAction { id: spaces; text: "Spaces"; iconName: "grid-vertical"; showToolTip: false; highlighted: root.selected && ShellState.panel === "left"; onClicked: ShellState.toggle("left", root.screenName) }
            RunningApps { id: runningApps; maximumWidth: Math.max(0, center.x - left.x - spaces.width - 2 * left.spacing); window: bar }
        }
        ClockPill {
            id: center
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.pillVerticalPadding
            highlighted: root.selected && ShellState.panel === "center"
            onClicked: ShellState.toggle("center", root.screenName)
        }
        Row {
            id: rightPills
            anchors.right: parent.right; anchors.rightMargin: 14; y: Theme.pillVerticalPadding
            spacing: 8
            TrayPill { id: tray; window: bar; maximumWidth: Math.max(0, bar.width - 14 - right.width - clipboardButton.width - center.x - center.width - 24) }
            ClipboardButton { id: clipboardButton; screenName: root.screenName }
            StatusPill {
                id: right
                highlighted: root.selected && ShellState.panel === "right"
                onClicked: ShellState.toggle("right", root.screenName)
            }
        }
    }
    PanelWindow {
        id: moduleWindow
        screen: root.screen
        visible: root.screenName === ShellState.pluginMonitor && !!ShellState.pluginId
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-module"
        // Keep focus stable while the anchored popup is open. Reacquiring it
        // on dismissal can redirect the stationary pointer away from the bar.
        WlrLayershell.keyboardFocus: visible && (ShellState.panel === "module" || root.popupOpen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // The backdrop still fills the screen; module input leaves the pills to the bar.
        mask: Region { x: 0; y: Theme.pillHeight; width: moduleWindow.width; height: Math.max(0, moduleWindow.height - y) }
        ModuleLoader {
            anchors.fill: parent
            enabled: !root.sharedModules
            visible: !root.sharedModules
            screenName: root.sharedModules ? "__shared__" : root.screenName
            readyToLoad: !leftDrawer.visible && !rightDrawer.visible
        }
    }
    DrawerWindow {
        id: leftDrawer
        screen: root.screen
        side: "left"
        opened: root.selected && ShellState.panel === "left"
        onVisibleChanged: root.syncModuleSurface()
        contentSource: Qt.resolvedUrl("../drawers/LibraryDrawer.qml")
    }
    DrawerWindow {
        id: rightDrawer
        screen: root.screen
        side: "right"
        opened: root.selected && ShellState.panel === "right"
        onVisibleChanged: root.syncModuleSurface()
        contentSource: Qt.resolvedUrl("../drawers/ControlDrawer.qml")
    }
    PanelWindow {
        screen: root.screen
        visible: root.selected && ShellState.panel === "profile" && !leftDrawer.visible && !rightDrawer.visible
        implicitWidth: Math.min(380, root.screenWidth - 32); implicitHeight: 320
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
        implicitWidth: Math.min(1240, root.screenWidth - 28)
        implicitHeight: Math.min(root.screenWidth < 900 ? 700 : 600, root.screenHeight - Theme.pillHeight - 24)
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
    ClipboardPopup {
        barWindow: bar
        screenName: root.screenName
        readyToOpen: !leftDrawer.visible && !rightDrawer.visible
    }
    PanelWindow {
        screen: root.screen
        visible: Attention.toast !== "" && ShellState.panel !== "center"
            && (root.screenName === Attention.toastMonitor
                || (!Quickshell.screens.some(s => s.name === Attention.toastMonitor) && root.screen === Quickshell.screens[0]))
        anchors { top: true; right: true }
        margins.top: Theme.pillHeight + 6
        margins.right: 14
        implicitWidth: Math.min(380, root.screenWidth - 28); implicitHeight: toastContent.item ? toastContent.item.implicitHeight : 0
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "zephyrus-shell-toast"
        Loader {
            id: toastContent
            anchors.fill: parent
            active: parent.visible
            source: Qt.resolvedUrl("../attention/NotificationToast.qml")
            onLoaded: {
                item.summary = Qt.binding(() => Attention.toast);
                item.body = Qt.binding(() => Attention.toastNotification ? Attention.toastNotification.body : "");
                item.appName = Qt.binding(() => Attention.toastNotification ? Attention.toastNotification.appName : "");
            }
        }
        Connections {
            target: toastContent.item
            function onOpened() { Attention.dismissToast(); ShellState.toggle("center", root.screenName); }
            function onDismissed() { Attention.dismissToast(); }
        }
    }
}
