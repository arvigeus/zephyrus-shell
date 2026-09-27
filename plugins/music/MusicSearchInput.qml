import QtQuick
import QtQuick.Layouts
import "../../widgets" as W

Item {
    id: root
    property string text: ""
    property string placeholderText: "Search…"
    property int fieldHeight: 40
    signal userTextEdited(string text)
    signal accepted()
    signal downPressed()
    implicitHeight: fieldHeight

    function focusField() {
        input.forceActiveFocus();
    }

    W.SearchField {
        id: input
        anchors.fill: parent
        rightPadding: 42
        text: root.text
        placeholderText: root.placeholderText
        implicitHeight: root.fieldHeight
        // TextField.textEdited has no payload; read the current field value.
        onTextEdited: root.userTextEdited(input.text)
        onAccepted: root.accepted()
        Keys.onDownPressed: event => {
            root.downPressed();
            event.accepted = true;
        }
    }

    W.IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        iconName: root.text.length > 0 ? "x" : "search"
        iconSize: 16
        text: root.text.length > 0 ? "Clear search" : "Search"
        onClicked: {
            if (root.text.length > 0) root.userTextEdited("");
            input.forceActiveFocus();
        }
    }
}
