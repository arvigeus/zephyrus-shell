import QtQuick
import Quickshell.Services.SystemTray
import "../core"
import "../widgets"

Item {
    id: root
    required property var window
    property real maximumWidth: 240
    width: Math.min(row.implicitWidth, maximumWidth)
    height: Theme.pillControlHeight
    visible: width > 0
    clip: true
    PillBackground { anchors.fill: parent; z: -1 }
    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: row.implicitWidth; contentHeight: root.height
        flickableDirection: Flickable.HorizontalFlick
        WheelScroll { view: view; horizontal: true }
        Row {
            id: row
            spacing: 6
            Repeater {
                model: SystemTray.items
                BarAction {
                    id: trayButton
                    required property var modelData
                    width: Theme.pillControlHeight
                    text: modelData.title || modelData.id
                    contentItem: Image { source: trayButton.modelData.icon; sourceSize.width: 22; sourceSize.height: 22; fillMode: Image.PreserveAspectFit }
                    onClicked: { if (modelData.onlyMenu) openMenu(); else modelData.activate(); }
                    function openMenu() {
                        const point = mapToItem(root.window.contentItem, 0, height);
                        if (modelData.hasMenu) modelData.display(root.window, point.x, point.y);
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: trayButton.openMenu() }
                }
            }
        }
    }
}
