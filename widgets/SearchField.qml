import QtQuick
import QtQuick.Controls
import "../core/theme"

TextField {
    implicitHeight: 46
    color: Theme.text
    placeholderTextColor: Theme.muted
    font.pixelSize: 15
    leftPadding: 16
    rightPadding: 16
    selectByMouse: true
    background: Rectangle {
        radius: Theme.controlRadius; color: Theme.surface
        border.color: parent.activeFocus ? Theme.accent : Theme.border
    }
}
