import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core/theme"
import "." as W

Popup {
    id: root
    property var images: []
    property string title: "Images"
    property int currentIndex: 0
    property bool zoomed: false
    property var returnFocus: null
    readonly property var currentImage: images[currentIndex] || ({})
    readonly property string imageSource: typeof currentImage === "string" ? currentImage : currentImage.url || ""
    width: parent.width
    height: parent.height
    modal: true
    focus: true
    padding: 14
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    function show(items, index, caption) {
        returnFocus = root.parent && root.parent.Window.window ? root.parent.Window.window.activeFocusItem : null;
        images = items || [];
        currentIndex = Math.max(0, Math.min(index || 0, images.length - 1));
        title = caption || "Images";
        zoomed = false;
        open();
    }
    function step(delta) {
        if (images.length) currentIndex = (currentIndex + delta + images.length) % images.length;
    }
    onCurrentIndexChanged: { pan.contentX = 0; pan.contentY = 0; }
    onOpened: contentItem.forceActiveFocus()
    onClosed: {
        images = [];
        if (returnFocus) returnFocus.forceActiveFocus();
        returnFocus = null;
    }
    background: Rectangle { color: Theme.scrim(0.97); border.color: Theme.border; radius: Theme.radius }
    contentItem: ColumnLayout {
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Left) root.step(-1);
            else if (event.key === Qt.Key_Right) root.step(1);
            else if (event.key === Qt.Key_Home) root.currentIndex = 0;
            else if (event.key === Qt.Key_End) root.currentIndex = root.images.length - 1;
            else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_Minus) root.zoomed = !root.zoomed;
            else { event.accepted = false; return; }
            event.accepted = true;
        }
        RowLayout {
            Layout.fillWidth: true
            W.Label { text: root.title; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
            W.Label { text: root.images.length ? (root.currentIndex + 1) + " / " + root.images.length : ""; color: Theme.muted }
            W.Action { text: root.zoomed ? "Fit" : "Zoom"; onClicked: root.zoomed = !root.zoomed }
            W.IconButton { iconName: "x"; text: "Close gallery"; onClicked: root.close() }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Flickable {
                id: pan
                anchors.fill: parent
                clip: true
                contentWidth: Math.max(width, fullImage.width)
                contentHeight: Math.max(height, fullImage.height)
                boundsBehavior: Flickable.StopAtBounds
                Image {
                    id: fullImage
                    source: root.visible ? root.imageSource : ""
                    sourceSize.width: root.zoomed ? 3840 : 1920
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    width: root.zoomed ? Math.max(pan.width, implicitWidth) : pan.width
                    height: root.zoomed ? Math.max(pan.height, implicitHeight) : pan.height
                }
            }
            BusySpinner { anchors.centerIn: parent; running: fullImage.status === Image.Loading }
            W.Label { anchors.centerIn: parent; visible: fullImage.status === Image.Error; text: "This image could not load."; color: Theme.muted }
            W.IconButton { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; visible: root.images.length > 1; iconName: "chevron-left"; text: "Previous image"; highlighted: true; onClicked: root.step(-1) }
            W.IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: root.images.length > 1; iconName: "chevron-right"; text: "Next image"; highlighted: true; onClicked: root.step(1) }
        }
    }
}
