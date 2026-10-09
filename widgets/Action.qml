import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core/theme"

Button {
    id: root
    property string iconName: ""
    property url iconArtwork: ""
    property string toolTip: ""
    property bool destructive: false
    property real cornerRadius: Theme.controlRadius
    // Preserve the surface RGB while fading alpha; transparent black produces
    // a dark flash halfway through a light-theme hover animation.
    property color idleColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0)
    property int textAlignment: Text.AlignHCenter
    implicitHeight: 42
    implicitWidth: Math.max(42, contentItem.implicitWidth + 28)
    hoverEnabled: true
    font.family: Theme.font
    font.pixelSize: Theme.sp(14)
    Accessible.name: text
    ToolTip.visible: (hovered || activeFocus) && ToolTip.text.length > 0
    ToolTip.text: toolTip
    ToolTip.delay: 800
    contentItem: RowLayout {
        spacing: 8
        Icon { visible: !!root.iconName && !root.iconArtwork.toString(); name: root.iconName; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
        Loader {
            active: !!root.iconArtwork.toString()
            visible: active
            Layout.preferredWidth: 20; Layout.preferredHeight: 20
            source: active ? Qt.resolvedUrl("AppIcon.qml") : ""
            onLoaded: item.artwork = Qt.binding(() => root.iconArtwork)
        }
        Label {
            text: root.text
            Layout.fillWidth: true
            color: !root.enabled ? Theme.muted : root.highlighted ? Theme.accent : root.destructive ? Theme.danger : Theme.text
            horizontalAlignment: root.textAlignment
            verticalAlignment: Text.AlignVCenter
        }
    }
    background: Rectangle {
        radius: root.cornerRadius
        color: root.down ? Theme.raised : root.highlighted ? Theme.accentSurface : root.hovered ? Theme.surface : root.idleColor
        border.color: root.activeFocus ? Theme.accent : "transparent"
        border.width: root.activeFocus ? 2 : 1
        opacity: root.enabled ? 1 : 0.5
        Rectangle { visible: root.highlighted; x: 0; y: 10; width: 2; height: parent.height - 20; color: Theme.accent }
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
