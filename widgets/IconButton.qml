import QtQuick
import "../core"
Action {
    id: root
    property string iconName: "settings"
    property int iconSize: 24
    implicitWidth: 42
    contentItem: Item { implicitWidth: root.iconSize; implicitHeight: root.iconSize; Icon { anchors.centerIn: parent; width: root.iconSize; height: root.iconSize; name: root.iconName; opacity: root.enabled ? 1 : 0.4 } }
}
