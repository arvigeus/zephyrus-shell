import QtQuick
import "../core"
import "../widgets"

BarAction {
    id: root
    property string screenName: ShellState.monitor
    objectName: "clipboardButton"
    text: "Clipboard history"; iconName: "clipboard"
    toolTip: text
    highlighted: ShellState.monitor === screenName && ShellState.panel === "clipboard"
    contentItem: Item {
        implicitWidth: 20; implicitHeight: 20
        Icon { anchors.centerIn: parent; name: root.iconName; width: 20; height: 20 }
    }
    onClicked: ShellState.toggle("clipboard", screenName)
}
