import QtQuick
import QtQuick.Layouts
import "../core/theme"
import "." as W

W.Action {
    id: root
    property url imageSource: ""
    property string fallbackIcon: ""
    property string subtitle: ""
    property string badge: ""
    property bool favorite: false
    property int imageFillMode: Image.PreserveAspectFit
    padding: 5
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.highlighted || root.hovered ? Theme.accentSurface : "transparent"
        border.width: root.highlighted || root.activeFocus ? 2 : 0
        border.color: Theme.accent
    }
    contentItem: ColumnLayout {
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surface
            radius: Theme.controlRadius
            clip: true
            W.CrossfadeImage {
                id: artwork
                anchors.fill: parent; anchors.margins: 3
                source: root.imageSource
                fillMode: root.imageFillMode
                imageWidth: 400
            }
            Column {
                visible: !artwork.hasImage
                anchors.centerIn: parent
                width: parent.width - 18
                spacing: 10
                W.Icon { visible: !!root.fallbackIcon; anchors.horizontalCenter: parent.horizontalCenter; name: root.fallbackIcon; width: 30; height: 30; opacity: 0.55 }
                W.Label { width: parent.width; text: root.text; color: Theme.muted; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; maximumLineCount: 4 }
            }
            Rectangle {
                visible: !!root.badge
                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
                width: badgeText.implicitWidth + 16; height: 24
                radius: Theme.controlRadius; color: Theme.scrim(0.87)
                W.Label { id: badgeText; anchors.centerIn: parent; text: root.badge; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
            }
            Rectangle {
                visible: root.favorite
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                width: 30; height: 30; radius: 15; color: Theme.scrim(0.87)
                W.Icon { anchors.centerIn: parent; name: "star-filled"; width: 18; height: 18 }
            }
        }
        W.Label {
            Layout.fillWidth: true; Layout.preferredHeight: 34
            text: root.text; font.family: Theme.font; font.pixelSize: Theme.sp(13); maximumLineCount: 2
            wrapMode: Text.Wrap; verticalAlignment: Text.AlignTop
        }
        W.Label {
            visible: !!root.subtitle
            Layout.fillWidth: true; Layout.preferredHeight: visible ? 18 : 0
            text: root.subtitle; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11)
        }
    }
}
