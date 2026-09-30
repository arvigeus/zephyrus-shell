import QtQuick
import "../WindowOrder.js" as WindowOrder

QtObject {
    id: root
    property var toplevels: []
    property var clients: []
    readonly property var windows: publishedWindows
    property var publishedWindows: []
    readonly property var pendingWindows: WindowOrder.ordered(toplevels, clients)

    // A clients response updates individual QObjects synchronously. Publish only
    // after that batch finishes, so buttons never sort mixed old/new geometry.
    onPendingWindowsChanged: Qt.callLater(root.publish)
    function publish() {
        const next = pendingWindows;
        if (next.length === publishedWindows.length
            && next.every((window, index) => window === publishedWindows[index])) return;
        publishedWindows = next;
    }
}
