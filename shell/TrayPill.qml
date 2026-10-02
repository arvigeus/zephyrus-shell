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
                TrayButton {
                    required property var modelData
                    trayItem: modelData
                    barWindow: root.window
                }
            }
        }
    }
}
