pragma Singleton
import QtQuick
import "theme" as Design

// Compatibility facade for plugins importing core. Tokens live in theme/Theme.qml.
QtObject {
    readonly property color background: Design.Theme.background
    readonly property color surface: Design.Theme.surface
    readonly property color raised: Design.Theme.raised
    readonly property color border: Design.Theme.border
    readonly property color text: Design.Theme.text
    readonly property color muted: Design.Theme.muted
    readonly property color accent: Design.Theme.accent
    readonly property color accentSurface: Design.Theme.accentSurface
    readonly property color danger: Design.Theme.danger
    readonly property color accentText: Design.Theme.accentText
    readonly property string font: Design.Theme.font
    readonly property int radius: Design.Theme.radius
    readonly property int controlRadius: Design.Theme.controlRadius
    readonly property int gap: Design.Theme.gap
    readonly property int moduleMargin: Design.Theme.moduleMargin
    readonly property int moduleTopMargin: Design.Theme.moduleTopMargin
    readonly property int pillHeight: Design.Theme.pillHeight
    readonly property int pillControlHeight: Design.Theme.pillControlHeight
    readonly property int pillVerticalPadding: Design.Theme.pillVerticalPadding
    readonly property int pillBottomPadding: Design.Theme.pillBottomPadding
    readonly property int catalogueSearchWidth: Design.Theme.catalogueSearchWidth
    function scrim(opacity) { return Design.Theme.scrim(opacity); }
}
