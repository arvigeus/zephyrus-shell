import QtQuick
import QtQuick.Layouts
import "../core/theme"
import "../widgets"

Rectangle {
    id: root
    property string summary: ""
    property string body: ""
    property string appName: ""
    signal opened()
    signal dismissed()
    implicitWidth: 380
    implicitHeight: content.implicitHeight + 24
    color: Theme.surface
    radius: Theme.radius
    border.color: Theme.border
    MouseArea { anchors.fill: parent; onClicked: root.opened() }
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Icon { name: "bell"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
            Label { text: root.appName || "Notification"; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
            IconButton { iconName: "x"; iconSize: 16; implicitWidth: 32; implicitHeight: 32; text: "Hide notification popup"; onClicked: root.dismissed() }
        }
        Label { text: root.summary; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; font.weight: Font.DemiBold }
        Label { text: root.body; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3; color: Theme.muted }
    }
}
