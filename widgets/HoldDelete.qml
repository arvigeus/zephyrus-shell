import QtQuick
import QtQuick.Controls
import "../core"
import "." as W

W.IconButton {
    id: root
    property bool torrent: false
    signal activated()
    iconName: "trash-2"
    text: torrent ? "Hold to delete torrent and all its downloaded files" : "Hold to delete local file"
    onDownChanged: {
        hold.stop(); fill.stop();
        progress.width = 0;
        if (down) { hold.start(); fill.start(); }
    }
    Timer { id: hold; interval: 1300; repeat: false; onTriggered: root.activated() }
    Rectangle {
        id: progress
        anchors.bottom: parent.bottom; anchors.left: parent.left
        height: 3; width: 0; radius: 1
        color: Theme.danger
    }
    NumberAnimation { id: fill; target: progress; property: "width"; from: 0; to: root.width; duration: 1300 }
}
