import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets" as W

RowLayout {
    id: root
    objectName: "screenshot-action"
    property alias popup: menu
    spacing: 0

    function capture(delay) {
        const command = ["python3", Paths.file("scripts/screenshot.py"), "region", "--edit"];
        if (delay) {
            command.push("--delay", String(delay));
            ShellState.dismissPanel();
        }
        External.launch(command, null);
    }

    W.Action {
        objectName: "screenshot-capture"
        iconName: "camera"; text: "Screenshot"; Layout.fillWidth: true
        toolTip: "Capture an area now"
        onClicked: root.capture(0)
    }
    W.IconButton {
        id: arrow
        objectName: "screenshot-options"
        iconName: "chevron-down"; text: "Screenshot delay"
        onClicked: menu.visible ? menu.close() : menu.open()
        Menu {
            id: menu
            objectName: "screenshot-delay-menu"
            popupType: Popup.Item
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            x: arrow.width - width; y: arrow.height
            width: 220
            background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
            Repeater {
                model: [3, 5, 10]
                MenuItem {
                    required property int modelData
                    objectName: "screenshot-delay-" + modelData
                    text: "Select area in " + modelData + " s"
                    Accessible.description: "Wait " + modelData + " seconds, then select an area of the frozen screen"
                    contentItem: W.Label { text: parent.text; color: parent.highlighted ? Theme.accent : Theme.text }
                    background: Rectangle { color: parent.highlighted ? Theme.raised : "transparent" }
                    onTriggered: root.capture(modelData)
                }
            }
        }
    }
}
