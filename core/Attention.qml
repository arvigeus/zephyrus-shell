pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

QtObject {
    id: root
    property bool quiet: false
    readonly property var notifications: server.trackedNotifications
    readonly property int count: notifications.values.length
    property string toast: ""
    property var toastNotification: null
    property string toastMonitor: ""
    function dismissToast() { toast = ""; toastNotification = null; toastTimer.stop(); }
    property Connections toastClosed: Connections {
        target: root.toastNotification
        function onClosed() { root.dismissToast(); }
    }
    property NotificationServer server: NotificationServer {
        actionsSupported: true
        bodyMarkupSupported: false
        onNotification: notification => {
            notification.tracked = true;
            // Bound memory even when clients send notifications indefinitely.
            const entries = trackedNotifications.values;
            if (entries.length > 100) entries[0].dismiss();
            if (!root.quiet && !notification.lastGeneration) {
                root.toastNotification = notification;
                root.toast = notification.summary || notification.appName || "Notification";
                root.toastMonitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                root.toastTimer.restart();
            }
        }
    }
    onQuietChanged: if (quiet) dismissToast()
    property Timer toastTimer: Timer { interval: 6000; onTriggered: root.dismissToast() }
    function clear() { dismissToast(); notifications.values.slice().forEach(n => n.dismiss()); }
}
