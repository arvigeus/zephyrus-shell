import QtQuick
import "../core"
import "../widgets"
Action {
    id: root
    property var title: ({})
    text: title.title || ""
    padding: 5
    background: Rectangle { radius: 6; color: root.highlighted || root.hovered ? Theme.accentSurface : "transparent"; border.width: root.highlighted || root.activeFocus ? 2 : 0; border.color: Theme.accent }
    contentItem: Column {
        spacing: 8
        Rectangle {
            width: parent.width; height: root.height - 48
            color: Theme.surface; radius: 6
            
            CrossfadeImage {
                anchors.fill: parent; anchors.margins: 3
                source: root.title.poster || ""
                fillMode: Image.PreserveAspectFit
                imageWidth: 400
            }
            Label { anchors.centerIn: parent; width: parent.width - 20; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; text: root.text; visible: !root.title.poster }
        }
        Label { width: parent.width; height: 30; text: root.text; font.pixelSize: 13; maximumLineCount: 2; wrapMode: Text.Wrap }
    }
}
