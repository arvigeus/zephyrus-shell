import QtQuick
import QtQuick.Controls.Material as MaterialControls
import "../core/theme"

MaterialControls.BusyIndicator {
    // Use the rotating ring consistently, independent of the desktop's style.
    property color color: Theme.text
    MaterialControls.Material.accent: color
    padding: 0
    implicitWidth: 28
    implicitHeight: 28
}
