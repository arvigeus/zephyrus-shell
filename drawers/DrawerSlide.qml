import QtQuick

Item {
    id: root
    required property string side
    required property url contentSource
    property bool opened: false
    property real progress: 0
    readonly property alias item: content.item
    readonly property bool showing: opened || progress > 0
    clip: true
    onOpenedChanged: progress = opened ? 1 : 0
    Component.onCompleted: progress = opened ? 1 : 0
    Behavior on progress { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Loader {
        id: content
        x: (root.side === "left" ? -1 : 1) * width * (1 - root.progress)
        width: root.width; height: root.height
        active: root.showing
        enabled: root.opened
        source: root.contentSource
    }
}
