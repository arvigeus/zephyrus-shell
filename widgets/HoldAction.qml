import QtQuick
import "../core"
import "." as W

W.IconButton {
    id: root
    property int holdDuration: 1300
    signal activated()
    onDownChanged: {
        hold.stop();
        fill.stop();
        progress.width = 0;
        if (down) { hold.start(); fill.start(); }
    }
    Timer { id: hold; interval: root.holdDuration; repeat: false; onTriggered: root.activated() }
    Rectangle {
        id: progress
        anchors.bottom: parent.bottom; anchors.left: parent.left
        height: 3; width: 0; radius: 1
        color: Theme.danger
    }
    NumberAnimation { id: fill; target: progress; property: "width"; from: 0; to: root.width; duration: root.holdDuration }
}
