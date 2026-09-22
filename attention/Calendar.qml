import QtQuick
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    readonly property int offset: (month.getDay() + 6) % 7
    Layout.fillWidth: true
    function move(delta) { month = new Date(month.getFullYear(), month.getMonth() + delta, 1); }
    RowLayout {
        Layout.fillWidth: true
        Label { text: Qt.formatDate(root.month, "MMMM yyyy"); font.pixelSize: 20; Layout.fillWidth: true }
        Action { iconName: "arrow-left"; Accessible.name: "Previous month"; onClicked: root.move(-1) }
        Action { iconName: "chevron-right"; Accessible.name: "Next month"; onClicked: root.move(1) }
    }
    GridLayout {
        columns: 7; rowSpacing: 3; columnSpacing: 3; Layout.fillWidth: true
        Repeater {
            model: ["M", "T", "W", "T", "F", "S", "S"]
            Label { required property string modelData; text: modelData; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredHeight: 26 }
        }
        Repeater {
            model: 42
            Rectangle {
                required property int index
                readonly property date day: new Date(root.month.getFullYear(), root.month.getMonth(), index - root.offset + 1)
                readonly property bool isToday: day.toDateString() === root.today.toDateString()
                Layout.fillWidth: true; Layout.preferredHeight: 32
                radius: Theme.controlRadius; color: isToday ? Theme.accent : "transparent"
                Label { anchors.centerIn: parent; text: parent.day.getDate(); color: parent.isToday ? Theme.background : parent.day.getMonth() === root.month.getMonth() ? Theme.text : Theme.muted; opacity: parent.day.getMonth() === root.month.getMonth() ? 1 : 0.4 }
            }
        }
    }
}
