import QtQuick
import QtQuick.Controls
import "../core"
import "../widgets"

Item {
    id: root
    property bool readyToLoad: true
    property bool loadStarted: false
    readonly property var entry: Plugins.find(ShellState.pluginId)
    // Modules may declare property url backgroundImage, resolved relative to their QML.
    readonly property url backgroundImage: moduleLoader.item && moduleLoader.item.backgroundImage !== undefined ? moduleLoader.item.backgroundImage : ""
    Rectangle {
        anchors.fill: parent
        color: root.backgroundImage.toString() ? Theme.background : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.88)
    }
    Image {
        anchors.fill: parent
        source: root.backgroundImage
        fillMode: Image.PreserveAspectCrop
    }
    Shortcut { sequence: "Escape"; onActivated: ShellState.close() }
    // Wait for the drawer's exit animation, then allow a frame for the loading UI.
    Timer {
        interval: 32
        running: root.readyToLoad && !root.loadStarted
        onTriggered: root.loadStarted = true
    }
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !root.loadStarted || moduleLoader.status === Loader.Loading
        BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible }
        Label { text: "Loading " + (root.entry ? root.entry.name : "space") + "…"; color: Theme.muted }
    }
    Loader {
        id: moduleLoader
        objectName: "moduleContent"
        active: root.loadStarted
        asynchronous: true
        visible: status === Loader.Ready
        anchors.fill: parent
        anchors.margins: 28
        anchors.topMargin: 80
        source: root.entry ? root.entry.entry : ""
        onLoaded: {
            item.host = host;
            root.forceActiveFocus();
            if (typeof item.activate === "function") item.activate();
        }
    }
    Label {
        anchors.centerIn: parent
        visible: !root.entry || moduleLoader.status === Loader.Error
        text: "This space could not load. Close it with Escape or Desktop, then reload spaces."
        color: Theme.danger
        width: Math.min(500, parent.width - 56); wrapMode: Text.Wrap
    }
    Component.onCompleted: forceActiveFocus()
    QtObject {
        id: host
        readonly property int apiVersion: 1
        function close() { ShellState.close(); }
        function back() { ShellState.backToSpaces(); }
    }
}
