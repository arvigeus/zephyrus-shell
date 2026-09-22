import QtQuick
import QtQuick.Layouts
import "../core"

Rectangle {
    id: root
    property string title
    property string subtitle
    property string symbol
    property bool on: false
    property bool available: true
    signal toggled()
    signal expanded()
    implicitHeight: 82
    color: on ? Theme.accentSurface : Theme.surface
    radius: Theme.controlRadius
    Rectangle { x: 0; y: 14; width: 2; height: parent.height - 28; color: root.on ? Theme.accent : Theme.border }
    RowLayout {
        anchors.fill: parent; anchors.margins: 10; spacing: 2
        Action {
            Layout.fillWidth: true; Layout.fillHeight: true
            enabled: root.available
            text: root.title + ": " + root.subtitle
            background: Rectangle { color: parent.hovered ? Theme.raised : "transparent"; radius: Theme.controlRadius; border.width: parent.activeFocus ? 2 : 0; border.color: Theme.text }
            contentItem: RowLayout {
                spacing: 10
                Icon { name: root.symbol }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    Text { text: root.title; font.pixelSize: 15; font.bold: true; color: Theme.text }
                    Text { text: root.subtitle; font.pixelSize: 12; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText }
                }
            }
            onClicked: root.toggled()
        }
        Rectangle { width: 1; Layout.preferredHeight: 34; color: Theme.border }
        Action {
            text: "›"; Accessible.name: "Choose " + root.title; Layout.preferredWidth: 36
            enabled: root.available
            contentItem: Icon { name: "chevron-right" }
            background: Rectangle { radius: Theme.controlRadius; color: parent.hovered ? Theme.raised : "transparent"; border.width: parent.activeFocus ? 2 : 0; border.color: Theme.text }
            onClicked: root.expanded()
        }
    }
}
