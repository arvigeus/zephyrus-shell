import QtQuick
import QtQuick.Layouts
import "../core"
import "." as W

W.IconButton {
    id: root
    property int holdDuration: 1300
    property bool showLabel: false
    property bool activatedWhileDown: false
    signal activated()
    implicitWidth: Math.max(42, contentItem.implicitWidth + (showLabel ? 28 : 0))
    contentItem: RowLayout {
        spacing: 8
        W.Icon { name: root.iconName; Layout.preferredWidth: root.iconSize; Layout.preferredHeight: root.iconSize; opacity: root.enabled ? 1 : 0.4 }
        W.Label { visible: root.showLabel; text: root.text; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    }
    onDownChanged: {
        hold.stop();
        fill.stop();
        progress.width = 0;
        if (down && enabled && visible) { activatedWhileDown = false; hold.start(); fill.start(); }
    }
    onEnabledChanged: if (!enabled) { hold.stop(); fill.stop(); progress.width = 0; }
    onVisibleChanged: if (!visible) { hold.stop(); fill.stop(); progress.width = 0; }
    Timer { id: hold; interval: root.holdDuration; repeat: false; onTriggered: if (root.down && root.enabled && root.visible && !root.activatedWhileDown) { root.activatedWhileDown = true; root.activated(); } }
    Rectangle {
        id: progress
        anchors.bottom: parent.bottom; anchors.left: parent.left
        height: 3; width: 0; radius: 1
        color: Theme.danger
    }
    NumberAnimation { id: fill; target: progress; property: "width"; from: 0; to: root.width; duration: root.holdDuration }
}
