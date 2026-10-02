import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

PanelWindow {
    id: root
    required property string side
    required property url contentSource
    property bool opened: false
    property bool searching: false
    property string initialQuery: ""
    onOpenedChanged: {
        if (opened) {
            searching = false; initialQuery = "";
            if (side === "left") Qt.callLater(() => { if (opened && slide.item) slide.item.forceActiveFocus(); });
        }
    }
    visible: slide.showing
    anchors { top: true; bottom: true; left: true; right: true }
    readonly property real drawerWidth: Math.min(side === "right" ? 490 : 390, width)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zephyrus-shell-drawer"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // A separate, non-overlapping hit area: inside clicks cannot dismiss the drawer.
    MouseArea {
        x: root.side === "left" ? root.drawerWidth : 0
        width: root.width - root.drawerWidth; height: root.height
        enabled: root.opened && !root.searching
        acceptedButtons: Qt.AllButtons
        onClicked: ShellState.dismissPanel()
    }
    DrawerSlide {
        id: slide
        x: root.side === "left" ? 0 : root.width - width
        width: root.drawerWidth; height: root.height
        side: root.side
        opened: root.opened
        retainContent: root.side === "right"
        contentSource: root.contentSource
    }
    Connections {
        target: root.side === "left" ? slide.item : null
        ignoreUnknownSignals: true
        function onSearchRequested(query) {
            root.initialQuery = query;
            root.searching = true;
        }
    }
    Loader {
        anchors.fill: parent
        active: root.searching && slide.showing
        enabled: root.opened
        sourceComponent: SpaceSearch { initialQuery: root.initialQuery }
    }
}
