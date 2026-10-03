pragma Singleton
import QtQuick
import "Defaults.js" as Bundled

QtObject {
    id: root
    property var settings: Bundled.settings
    readonly property var colors: settings.palettes[settings.mode]
    readonly property var icons: settings.icons || ({})
    readonly property string mode: settings.mode
    readonly property color background: colors.background
    readonly property color surface: colors.surface
    readonly property color raised: colors.raised
    readonly property color border: colors.border
    readonly property color text: colors.text
    readonly property color muted: colors.muted
    readonly property color accent: colors.accent
    readonly property color accentSurface: Qt.tint(surface, Qt.rgba(accent.r, accent.g, accent.b, 0.16))
    readonly property color danger: colors.danger
    readonly property color warning: colors.warning
    readonly property color success: colors.success
    function scrim(opacity) { return Qt.rgba(background.r, background.g, background.b, opacity); }
    readonly property color accentText: colors.accent_text
    readonly property string font: settings.font
    readonly property real fontSize: settings.font_size
    readonly property string monospaceFont: settings.monospace_font
    readonly property real monospaceFontSize: settings.monospace_font_size
    function sp(pixels) { return Math.round(pixels * fontSize / 11); }
    property string error: ""
    property var warnings: []
    property bool loaded: false
    signal reloadRequested()
    signal modeRequested(string mode)
    function refresh() { reloadRequested(); }
    function setMode(mode) { if (["dark", "light"].includes(mode)) modeRequested(mode); }
    readonly property int radius: 10
    readonly property int controlRadius: 5
    readonly property int moduleMargin: 28
    readonly property int moduleTopMargin: pillHeight + 14
    readonly property int pillRadius: 9
    readonly property int pillControlHeight: 34
    readonly property int pillVerticalPadding: 6
    readonly property int pillBottomPadding: 2
    readonly property int pillHeight: pillControlHeight + pillVerticalPadding + pillBottomPadding
    readonly property int gap: 12
    readonly property int catalogueSearchWidth: 420
}
