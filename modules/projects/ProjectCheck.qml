import QtQuick
import QtQuick.Controls
import "../../core"
import "../../widgets" as W

CheckBox {
    id: root
    implicitHeight: 36
    spacing: 10
    leftPadding: 2
    rightPadding: 2
    indicator: Rectangle {
        x: root.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20
        radius: Theme.controlRadius
        color: root.checked ? Theme.accent : Theme.background
        border.color: root.activeFocus ? Theme.accent : root.checked ? Theme.accent : Theme.border
        W.Icon {
            visible: root.checked
            anchors.centerIn: parent
            width: 15; height: 15
            name: "check"
        }
    }
    contentItem: W.Label {
        leftPadding: root.indicator.width + root.spacing
        text: root.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
