import QtQuick
import Quickshell
import "../core"
import "../widgets"

BarAction {
    id: root
    required property var trayItem
    required property var barWindow
    readonly property var applicationEntries: DesktopEntries.applications.values
    readonly property var desktopEntry: {
        const entries = applicationEntries;
        return (trayItem.id ? DesktopEntries.heuristicLookup(trayItem.id) : null)
            || (trayItem.title ? DesktopEntries.heuristicLookup(trayItem.title) : null);
    }
    readonly property bool missingThemeIcon: {
        const source = trayItem.icon.toString();
        // Quickshell's icon provider returns a blank, successful image for
        // missing theme names, so Image.Error alone cannot detect them.
        return source.startsWith("image://icon/") && !source.includes("?path=")
            && !Quickshell.hasThemeIcon(decodeURIComponent(source.slice(13).split("?")[0]));
    }
    width: Theme.pillControlHeight
    text: trayItem.tooltipTitle || trayItem.title || trayItem.id
    toolTip: text
    contentItem: Item {
        Image {
            id: trayImage
            anchors.centerIn: parent
            width: 22; height: 22
            source: root.missingThemeIcon ? "" : root.trayItem.icon
            sourceSize.width: 22; sourceSize.height: 22
            fillMode: Image.PreserveAspectFit
        }
        AppIcon {
            anchors.centerIn: parent
            width: 22; height: 22
            visible: !trayImage.source.toString() || trayImage.status === Image.Error
            icon: root.desktopEntry ? root.desktopEntry.icon : ""
        }
    }
    function requestAction(action) {
        dismissToolTip();
        ShellState.showDesktop();
        pending.action = action;
        pending.restart();
    }
    onClicked: requestAction(trayItem.onlyMenu ? "menu" : "activate")
    Timer {
        id: pending
        property string action: ""
        // Wait for exclusive module/drawer surfaces to release input before
        // asking the application to activate or creating its platform menu.
        interval: 50
        onTriggered: {
            if (!root.trayItem) return;
            if (action === "activate") root.trayItem.activate();
            else if (action === "secondary") root.trayItem.secondaryActivate();
            else if (root.trayItem.hasMenu) {
                const point = root.mapToItem(root.barWindow.contentItem, 0, root.height);
                root.trayItem.display(root.barWindow, point.x, point.y);
            }
        }
    }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.requestAction("menu") }
    TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: root.requestAction("secondary") }
    WheelHandler {
        onWheel: event => {
            const horizontal = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y);
            root.trayItem.scroll(horizontal ? event.angleDelta.x : event.angleDelta.y, horizontal);
            event.accepted = true;
        }
    }
}
