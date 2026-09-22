import QtQuick
import QtQuick.Controls
import "../core"

Slider {
    id: root
    implicitHeight: 36
    background: Rectangle {
        x: root.leftPadding; y: (root.height - height) / 2
        width: root.availableWidth; height: 3; radius: 1; color: Theme.raised
        Rectangle { width: root.visualPosition * parent.width; height: parent.height; radius: 1; color: root.enabled ? Theme.accent : Theme.muted }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: (root.height - height) / 2
        width: 8; height: 20; radius: 2
        color: root.enabled ? Theme.accent : Theme.muted
        border.width: root.activeFocus ? 3 : 0; border.color: Theme.text
    }
}
