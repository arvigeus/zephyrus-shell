import QtQuick
import QtQuick.Controls
import "../../core"
import "../../widgets" as W

MenuItem {
    id: root
    property bool destructive: false
    implicitHeight: 36
    leftPadding: 12
    rightPadding: 12
    contentItem: W.Label {
        text: root.text
        color: !root.enabled ? Theme.muted : root.destructive ? Theme.danger : root.highlighted ? Theme.accent : Theme.text
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.highlighted ? Theme.raised : "transparent"
    }
}
