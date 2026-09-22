import QtQuick
import Quickshell
import "../core"

Item {
    id: root
    property string icon: ""
    implicitWidth: 24; implicitHeight: 24
    Image {
        id: image
        anchors.fill: parent
        source: Quickshell.hasThemeIcon(root.icon) ? Quickshell.iconPath(root.icon) : ""
        sourceSize.width: root.width; sourceSize.height: root.height
        fillMode: Image.PreserveAspectFit
    }
}
