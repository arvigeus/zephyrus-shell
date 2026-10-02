pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#101115"
    readonly property color surface: "#191b21"
    readonly property color raised: "#252830"
    readonly property color border: "#32353f"
    readonly property color text: "#f1f2f6"
    readonly property color muted: "#a1a6b5"
    readonly property color accent: "#ff465c"
    readonly property color accentSurface: Qt.tint(surface, Qt.rgba(accent.r, accent.g, accent.b, 0.16))
    readonly property color danger: "#ff8090"
    function scrim(opacity) { return Qt.rgba(background.r, background.g, background.b, opacity); }
    readonly property color accentText: "#ffffff"
    readonly property string font: "sans-serif"
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
