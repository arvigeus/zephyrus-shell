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
    property bool externalWallpaper: false
    readonly property string screenName: screen ? screen.name : ""
    readonly property real screenWidth: screen ? screen.width : 0
    readonly property real screenHeight: screen ? screen.height : 0
    // The shell's single ModuleLoader, attached to whichever screen shows the module.
    required property ModuleLoader modules
    function syncModuleSurface() {
        if (!screen || screenName !== ShellState.moduleMonitor) return;
        modules.parent = moduleSurface;
        modules.readyToLoad = !leftDrawer.visible && !rightDrawer.visible;
    }
    Component.onCompleted: {
        if (!ShellState.monitor && screen && screen === Quickshell.screens[0]) ShellState.monitor = screenName;
        syncModuleSurface();
    }
    Component.onDestruction: {
        if (modules.parent === moduleSurface) modules.parent = null;
    }
    Connections {
        target: ShellState
        function onModuleMonitorChanged() { root.syncModuleSurface(); }
        function onPanelChanged() { Qt.callLater(root.syncModuleSurface); }
    }
    readonly property bool selected: !!screen && (ShellState.monitor === screenName || (!Quickshell.screens.some(s => s.name === ShellState.monitor) && screen === Quickshell.screens[0]))
    readonly property bool moduleShown: root.screenName === ShellState.moduleMonitor && !!ShellState.moduleId
    readonly property var pillWindow: interactionWindow.visible ? interactionWindow : bar
    readonly property bool popupOpen: languageButton.menuVisible || (root.selected && ["center", "clipboard"].includes(ShellState.panel))
    PanelWindow {
        screen: root.screen
        visible: !root.externalWallpaper
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
        // Stays mapped so its reserved zone never changes and tiled windows
        // do not move; it only accepts input while it holds the pills.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-bar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: root.pillWindow === bar ? pillMask : noInput
        Region {
            id: pillMask
            Region { item: spaces }
            Region { item: runningApps }
            Region { item: center }
            Region { item: rightPills }
        }
        Region { id: noInput }
        IdleInhibitor { window: root.pillWindow; enabled: KeepAwake.mode === "screen" && KeepAwake.active }
    }
    // A single set of pills moves with the visible interaction surface. The
    // passive desktop bar never owns keyboard focus; leaving a module unmaps
    // its exclusive surface, allowing the compositor to restore native focus.
    Item {
        parent: root.pillWindow.contentItem
        width: root.pillWindow.width; height: Theme.pillHeight
        z: 10
        Shortcut {
            sequence: "Escape"
            enabled: (root.screenName === ShellState.moduleMonitor && ShellState.panel === "module") || root.popupOpen
            onActivated: {
                if (languageButton.menuVisible) languageButton.menuVisible = false;
                else if (ShellState.panel === "center") {
                    if (attentionContent.item) attentionContent.item.dismiss();
                    else ShellState.dismissPanel();
                } else if (ShellState.panel === "clipboard") ShellState.dismissPanel();
                else ShellState.showDesktop();
            }
        }
        Row {
            id: left
            x: 14; y: Theme.pillVerticalPadding; spacing: 8
            BarAction { id: spaces; text: "Spaces"; iconName: "grid-vertical"; showToolTip: false; highlighted: root.selected && ShellState.panel === "left"; onClicked: ShellState.toggle("left", root.screenName) }
            RunningApps { id: runningApps; maximumWidth: Math.max(0, center.x - left.x - spaces.width - 2 * left.spacing); window: root.pillWindow }
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
            TrayPill { id: tray; window: root.pillWindow; maximumWidth: Math.max(0, root.pillWindow.width - 14 - right.width - clipboardButton.width - languageButton.width - center.x - center.width - 24) }
            LanguageButton { id: languageButton; barWindow: interactionWindow }
            ClipboardButton { id: clipboardButton; screenName: root.screenName }
            StatusPill {
                id: right
                highlighted: root.selected && ShellState.panel === "right"
                onClicked: ShellState.toggle("right", root.screenName)
            }
        }
    }
    // Popups that open the interaction surface anchor to it directly, so
    // dismissal never re-anchors them onto the passive bar.
    PanelWindow {
        id: interactionWindow
        screen: root.screen
        visible: root.moduleShown || root.popupOpen || languageButton.restoringInputFocus
        anchors { top: true; bottom: root.moduleShown; left: true; right: true }
        implicitHeight: Theme.pillHeight
        // Covers the persistent bar rather than reserving a second zone.
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: root.moduleShown && !leftDrawer.visible && !rightDrawer.visible ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "zephyrus-shell-interaction"
        // Keep Exclusive until unmapping. Setting None before unmapping can
        // clear the compositor's last focus while another layer still owns it.
        WlrLayershell.keyboardFocus: root.moduleShown && ShellState.panel !== "module" && !root.popupOpen
            ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
        mask: Region {
            Region { item: moduleInput; }
            Region { item: spaces }
            Region { item: runningApps }
            Region { item: center }
            Region { item: rightPills }
        }
        Item {
            id: moduleInput
            visible: root.moduleShown
            y: Theme.pillHeight; width: interactionWindow.width; height: Math.max(0, interactionWindow.height - y)
        }
        Item {
            id: moduleSurface
            // Desktop popups use a 42px interaction window. Hidden modules
            // retain full-screen geometry so opening one cannot reset layouts.
            width: root.screenWidth; height: root.screenHeight
            visible: root.moduleShown
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
        anchor.window: interactionWindow
        anchor.rect.x: (interactionWindow.width - width) / 2
        anchor.rect.y: Theme.pillHeight + 6
        implicitWidth: Math.min(1240, root.screenWidth - 28)
        implicitHeight: Math.min(root.screenWidth < 900 ? 700 : 600, root.screenHeight - Theme.pillHeight - 24)
        color: "transparent"
        // Wait for the popup surface before whitelisting it alongside the bar.
        onWindowConnected: Qt.callLater(() => { if (visible) attentionGrab.active = true; })
        onVisibleChanged: { if (!visible) attentionGrab.active = false; }
        HyprlandFocusGrab {
            id: attentionGrab
            windows: [attentionWindow, interactionWindow]
            onCleared: {
                if (root.selected && ShellState.panel === "center") ShellState.dismissPanel();
            }
        }
        Loader { id: attentionContent; anchors.fill: parent; active: parent.visible; sourceComponent: AttentionPanel {} }
    }
    ClipboardPopup {
        barWindow: interactionWindow
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
