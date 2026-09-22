pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

QtObject {
    id: root
    property bool quiet: false
    readonly property var notifications: server.trackedNotifications
    readonly property int count: notifications.values.length
    property string toast: ""
    property NotificationServer server: NotificationServer {
        actionsSupported: true
        bodyMarkupSupported: false
        onNotification: notification => {
            notification.tracked = true;
            // Bound memory even when clients send notifications indefinitely.
            const entries = trackedNotifications.values;
            if (entries.length > 100) entries[0].dismiss();
            if (!root.quiet) { root.toast = notification.summary; root.toastTimer.restart(); }
        }
    }
    property Timer toastTimer: Timer { interval: 6000; onTriggered: root.toast = "" }
    function clear() { notifications.values.slice().forEach(n => n.dismiss()); toast = ""; toastTimer.stop(); }
}
