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
    readonly property color warning: Design.Theme.warning
    readonly property color success: Design.Theme.success
    readonly property color accentText: Design.Theme.accentText
    readonly property string font: Design.Theme.font
    readonly property real fontSize: Design.Theme.fontSize
    readonly property string monospaceFont: Design.Theme.monospaceFont
    readonly property real monospaceFontSize: Design.Theme.monospaceFontSize
    readonly property string mode: Design.Theme.mode
    readonly property bool loaded: Design.Theme.loaded
    readonly property string error: Design.Theme.error
    readonly property var warnings: Design.Theme.warnings
    function sp(pixels) { return Design.Theme.sp(pixels); }
    function refresh() { Design.Theme.refresh(); }
    function setMode(mode) { Design.Theme.setMode(mode); }
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
