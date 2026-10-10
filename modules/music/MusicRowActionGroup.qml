import QtQuick
import QtQuick.Layouts

FocusScope {
    id: root

    property bool entityHovered: false
    readonly property bool revealed: entityHovered || actionHover.hovered || activeFocus
    default property alias actions: actionRow.data

    implicitWidth: actionRow.implicitWidth
    implicitHeight: actionRow.implicitHeight

    HoverHandler { id: actionHover }

    RowLayout {
        id: actionRow
        anchors.fill: parent
        spacing: 2
    }
}
