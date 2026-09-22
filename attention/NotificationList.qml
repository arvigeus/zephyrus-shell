import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    spacing: 14
    RowLayout {
        Layout.fillWidth: true
        Heading { text: "ATTENTION"; Layout.fillWidth: true }
        Action { text: "Clear notifications"; enabled: Attention.count > 0; onClicked: Attention.clear() }
    }
    Label { visible: Attention.count === 0; text: "You're all caught up."; color: Theme.muted; Layout.fillWidth: true }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; spacing: 8
        model: Attention.notifications.values.slice().reverse()
        delegate: Rectangle {
            id: card
            required property var modelData
            width: ListView.view.width
            implicitHeight: content.implicitHeight + 24
            radius: Theme.controlRadius; color: Theme.surface
            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: card.modelData.summary; Layout.fillWidth: true; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                    Action { iconName: "x"; Accessible.name: "Dismiss notification"; onClicked: card.modelData.dismiss() }
                }
                Label { text: card.modelData.body; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted }
                Flow {
                    Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: card.modelData.actions
                        Action { required property var modelData; text: modelData.text; onClicked: modelData.invoke() }
                    }
                }
            }
        }
        ScrollBar.vertical: ScrollBar {}
    }
}
