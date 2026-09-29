import QtQuick
import QtQuick.Layouts
import "../core"

RowLayout {
    id: root
    property real percent: 0
    property bool available: true
    spacing: 2
    implicitHeight: 8
    Repeater {
        model: [
            {start: 0, end: 60, color: "#58b87a"},
            {start: 60, end: 85, color: "#e1b957"},
            {start: 85, end: 100, color: "#e16c74"}
        ]
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredWidth: modelData.end - modelData.start
            implicitHeight: 8
            radius: 2
            color: Theme.raised
            clip: true
            Rectangle {
                width: parent.width * (root.available ? Math.max(0, Math.min(1, (root.percent - parent.modelData.start) / (parent.modelData.end - parent.modelData.start))) : 0)
                height: parent.height
                color: parent.modelData.color
            }
        }
    }
}
