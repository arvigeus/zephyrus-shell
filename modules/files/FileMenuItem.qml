import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../widgets"

// Cog-menu row. Return, Enter and Right activate it; Left and Space close the menu.
MenuItem {
    id: root
    property bool destructive: false
    signal activated()
    enabled: visible
    height: visible ? implicitHeight : 0
    implicitHeight: 42
    leftPadding: 12; rightPadding: 12
    contentItem: RowLayout {
        spacing: 8
        Icon { visible: root.destructive; name: "trash-2"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
        Label {
            Layout.fillWidth: true
            text: root.text
            color: root.destructive ? Theme.danger : root.highlighted ? Theme.accent : Theme.text
            verticalAlignment: Text.AlignVCenter
        }
    }
    background: Rectangle { color: !root.highlighted ? "transparent" : root.destructive ? Theme.accentSurface : Theme.raised }
    onTriggered: activated()
    Keys.onReturnPressed: event => { root.activated(); event.accepted = true; }
    Keys.onEnterPressed: event => { root.activated(); event.accepted = true; }
    Keys.onRightPressed: event => { root.activated(); event.accepted = true; }
    Keys.onLeftPressed: event => { root.menu.close(); event.accepted = true; }
    Keys.onSpacePressed: event => { root.menu.close(); event.accepted = true; }
}
