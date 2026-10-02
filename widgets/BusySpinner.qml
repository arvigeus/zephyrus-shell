import QtQuick
import QtQuick.Controls.Basic as Basic
import "../core/theme"

Basic.BusyIndicator {
    // Keep loading feedback readable regardless of the desktop's control style.
    property color color: Theme.text
    palette.dark: color
    padding: 0
    implicitWidth: 28
    implicitHeight: 28
}
