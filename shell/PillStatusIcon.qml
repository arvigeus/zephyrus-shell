import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"

Icon {
    id: root
    required property string description
    Layout.preferredWidth: 19
    Layout.preferredHeight: 19
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: root.description
    ToolTip.delay: 500
}
