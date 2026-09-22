import QtQuick
import QtQuick.Controls
import "../core"

ComboBox {
    id: root
    implicitHeight: 42
    hoverEnabled: true
    leftPadding: 14; rightPadding: 28
    contentItem: Text { text: root.displayText; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; textFormat: Text.PlainText }
    background: Rectangle { radius: Theme.controlRadius; color: root.hovered ? Theme.raised : Theme.surface; border.color: root.activeFocus ? Theme.accent : "transparent" }
    indicator: Icon { name: "chevron-down"; width: 18; height: 18; x: root.width - 26; anchors.verticalCenter: parent.verticalCenter }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: root.width
        contentItem: Text { text: root.textRole ? modelData[root.textRole] : modelData; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; textFormat: Text.PlainText }
        background: Rectangle { color: root.highlightedIndex === parent.index ? Theme.raised : Theme.surface }
        highlighted: root.highlightedIndex === index
    }
    popup: Popup {
        y: root.height + 4; width: root.width; padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 240)
        background: Rectangle { radius: Theme.controlRadius; color: Theme.surface; border.color: Theme.border }
        contentItem: ListView { id: choices; WheelScroll { view: choices } clip: true; implicitHeight: contentHeight; model: root.popup.visible ? root.delegateModel : null; currentIndex: root.highlightedIndex; ScrollBar.vertical: ScrollBar {} }
    }
}
