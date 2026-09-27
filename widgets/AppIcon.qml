import QtQuick
import Quickshell
import "../core/theme"

Item {
    id: root
    property string icon: ""
    property url artwork: ""
    implicitWidth: 24; implicitHeight: 24
    Image {
        id: image
        anchors.fill: parent
        source: root.artwork.toString() ? root.artwork : root.icon.length > 0 && Quickshell.hasThemeIcon(root.icon) ? Quickshell.iconPath(root.icon) : ""
        sourceSize.width: root.width; sourceSize.height: root.height
        fillMode: Image.PreserveAspectFit
    }
}
