import QtQuick
import QtQuick.Controls
import Quickshell
import "../core/theme"
import "../widgets"

Action {
    id: root
    property bool showToolTip: true
    readonly property bool toolTipVisible: tip.visible
    property bool toolTipReady: false
    function dismissToolTip() { toolTipReady = false; toolTipDelay.stop(); }
    implicitHeight: Theme.pillControlHeight
    cornerRadius: Theme.pillRadius
    idleColor: Theme.surface
    // Controls' native ToolTip can grab the bar's pointer input on Wayland.
    // A passive popup has an empty input region and never takes keyboard focus.
    ToolTip.visible: false
    onHoveredChanged: { if (!hovered) dismissToolTip(); }
    onDownChanged: { if (down) dismissToolTip(); }
    Timer {
        id: toolTipDelay
        interval: 800
        running: root.showToolTip && root.hovered && !root.down && !!root.text
        onTriggered: root.toolTipReady = true
    }
    PopupWindow {
        id: tip
        visible: root.toolTipReady && root.showToolTip && root.hovered && !root.down && !!root.text
        anchor.item: root
        anchor.rect.x: (root.width - width) / 2
        anchor.rect.y: root.height + 6
        implicitWidth: Math.min(tipLabel.implicitWidth, 480) + 20
        implicitHeight: tipLabel.implicitHeight + 12
        color: "transparent"
        mask: Region {}
        Rectangle {
            anchors.fill: parent
            radius: Theme.controlRadius
            color: Theme.background
            border.color: Theme.border
            Label { id: tipLabel; anchors.centerIn: parent; text: root.text; width: Math.min(implicitWidth, 480); elide: Text.ElideRight }
        }
    }
}
