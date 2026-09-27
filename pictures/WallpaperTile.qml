import QtQuick
import "../core"
import "../widgets" as W

Item {
    id: root
    required property string payload
    required property int index
    readonly property var wallpaper: JSON.parse(payload)
    property bool highlighted: false
    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#72080a0d"
        border.width: root.highlighted ? 2 : 1
        border.color: root.highlighted ? Theme.accent : pointer.containsMouse ? Theme.text : Theme.border
        clip: true

        W.CrossfadeImage {
            anchors.fill: parent
            anchors.margins: 2
            source: root.wallpaper.thumbLarge || root.wallpaper.preview || ""
            imageWidth: 700
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 28
            color: "#b80b0d12"
            W.Label {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                text: root.wallpaper.resolution || root.wallpaper.id
                color: Theme.text
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
