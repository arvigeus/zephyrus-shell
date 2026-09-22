import QtQuick
Image {
    property string name: "settings"
    source: name ? Qt.resolvedUrl("../assets/lucide/" + name + ".svg") : ""
    sourceSize.width: 24; sourceSize.height: 24
    fillMode: Image.PreserveAspectFit
}
