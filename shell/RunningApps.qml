import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../widgets"
import "../core"

Item {
    id: root
    required property var window
    property real maximumWidth: 240
    width: Math.min(row.implicitWidth, maximumWidth)
    height: 42
    clip: true
    Flickable {
        anchors.fill: parent; contentWidth: row.implicitWidth; contentHeight: 42
        flickableDirection: Flickable.HorizontalFlick
        Row {
            id: row; spacing: 6
            Repeater {
                model: ToplevelManager.toplevels
                Action {
                    id: windowButton
                    required property var modelData
                    width: 42
                    text: modelData.title || modelData.appId
                    highlighted: modelData.activated
                    contentItem: AppIcon { icon: windowButton.modelData.appId }
                    onClicked: modelData.activate()
                }
            }
            Repeater {
                model: SystemTray.items
                Action {
                    id: trayButton
                    required property var modelData
                    width: 42; text: modelData.title || modelData.id
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
