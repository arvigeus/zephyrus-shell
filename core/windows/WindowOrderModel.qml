import QtQuick
import QtQml.Models
import "../WindowOrder.js" as WindowOrder

QtObject {
    id: root
    property var toplevels: []
    property var clients: []
    readonly property var windows: publishedWindows
    property var publishedWindows: []
    // An IPC response changes each client's geometry in sequence. Observe those
    // signals directly and sort once when the batch ends; a sorting binding would
    // sort the whole list again for every client before publication is coalesced.
    onToplevelsChanged: Qt.callLater(root.publish)
    onClientsChanged: Qt.callLater(root.publish)
    Component.onCompleted: Qt.callLater(root.publish)
    property Instantiator geometryObservers: Instantiator {
        model: root.clients
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { Qt.callLater(root.publish); }
            function onWaylandChanged() { Qt.callLater(root.publish); }
        }
    }
    function publish() {
        const next = WindowOrder.ordered(toplevels, clients);
        if (next.length === publishedWindows.length
            && next.every((window, index) => window === publishedWindows[index])) return;
        publishedWindows = next;
    }
}
