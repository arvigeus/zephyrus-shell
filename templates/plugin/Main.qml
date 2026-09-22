import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../widgets"

ColumnLayout {
    property var host
    Label { text: "Your new space"; font.pixelSize: 24 }
    Label { text: "Replace this content with your module."; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Item { Layout.fillHeight: true }
    Action { text: "Back to spaces"; onClicked: host.back() }
}
