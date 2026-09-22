import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets" as W

RowLayout {
    id: root
    property string text: ""
    property string iconName: "play"
    property var options: []
    property int currentIndex: 0
    property alias popup: menu
    signal triggered(int index)
    spacing: 1
    W.Action {
        text: root.text; iconName: root.iconName
        onClicked: root.triggered(root.currentIndex)
        background: Rectangle { radius: Theme.controlRadius; topRightRadius: arrow.visible ? 0 : Theme.controlRadius; bottomRightRadius: arrow.visible ? 0 : Theme.controlRadius; color: parent.down ? Qt.darker(Theme.accent,1.2) : parent.hovered ? Qt.lighter(Theme.accent,1.1) : Theme.accent; border.color: parent.activeFocus ? Theme.text : "transparent"; border.width: 2 }
    }
    W.IconButton {
        id: arrow
        visible: root.options.length > 1
        iconName: "chevron-down"; text: "Choose " + root.text.toLowerCase()
        onClicked: menu.open()
        background: Rectangle { radius: Theme.controlRadius; topLeftRadius: 0; bottomLeftRadius: 0; color: parent.hovered ? Qt.lighter(Theme.accent,1.1) : Theme.accent; border.color: parent.activeFocus ? Theme.text : "transparent"; border.width: 2 }
        Menu {
            id: menu; popupType: Popup.Item; y: arrow.height; width: Math.min(440,root.Window.width - 48)
            background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
            Repeater {
                model: root.options
                MenuItem {
                    required property string modelData
                    required property int index
                    text: modelData
                    contentItem: W.Label { text: parent.text; color: parent.highlighted ? Theme.accent : Theme.text }
                    background: Rectangle { color: parent.highlighted ? Theme.raised : "transparent" }
                    onTriggered: { root.currentIndex=index; root.triggered(index); }
                }
            }
        }
    }
}
