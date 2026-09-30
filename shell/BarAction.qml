import QtQuick
import QtQuick.Controls
import "../core/theme"
import "../widgets"

Action {
    property bool showToolTip: true
    implicitHeight: Theme.pillControlHeight
    idleColor: Theme.surface
    ToolTip.visible: showToolTip && hovered && text.length > 0
}
