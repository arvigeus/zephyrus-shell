import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "attention"

ShellRoot {
    id: root
    property int notificationId: 0
    // Leave time for first-frame software rendering on slow test hosts.
    Component.onCompleted: Attention.toastTimer.interval = 30000
    function send(summary, replacement) {
        sender.command = ["notify-send", "--print-id", "--app-name=Zephyrus", summary, "Notifications appear above desktop windows."];
        if (replacement) sender.command = sender.command.concat(["--replace-id=" + notificationId]);
        sender.running = true;
    }
    Process {
        id: sender
        stdout: StdioCollector { onStreamFinished: root.notificationId = parseInt(text.trim()) }
    }
    FloatingWindow {
        implicitWidth: 380; implicitHeight: 200; color: "transparent"
        NotificationToast {
            id: toast
            width: 380; height: implicitHeight
            summary: Attention.toast
            body: Attention.toastNotification ? Attention.toastNotification.body : ""
            appName: Attention.toastNotification ? Attention.toastNotification.appName : ""
        }
    }
    Timer {
        interval: 100; repeat: true; running: true
        property int step: 0
        property int ticks: 0
        function fail(message) { console.error("NOTIFICATIONS FAIL:", message); stop(); Qt.quit(); }
        onTriggered: {
            if (++ticks > 80) { fail("Timeout at " + step); return; }
            if (step === 0) { root.send("Desktop notification", false); step = 1; }
            else if (step === 1 && !sender.running && Attention.count === 1 && Attention.toastNotification) {
                if (Attention.toast !== "Desktop notification" || toast.implicitHeight < 80) { fail("Popup content missing"); return; }
                step = 10; ticks = 0;
            } else if (step === 10 && ticks > 4) {
                if (toast.height < toast.implicitHeight) return;
                if (toast.summary !== "Desktop notification" || toast.body === "") { fail("Popup expired before capture"); return; }
                toast.grabToImage(result => {
                    if (!result.saveToFile(Paths.file("tests/artifacts/notification-popup.png"))) { fail("Capture failed"); return; }
                    Attention.dismissToast();
                    if (Attention.count !== 1) { fail("Hiding removed history"); return; }
                    Attention.quiet = true;
                    root.send("Quiet replacement", true); step = 2;
                }); step = -1;
            } else if (step === 2 && !sender.running && Attention.notifications.values[0].summary === "Quiet replacement") {
                if (Attention.count !== 1 || Attention.toast !== "") { fail("Quiet replacement displayed or duplicated"); return; }
                Attention.quiet = false; root.send("New notification", false); step = 3;
            } else if (step === 3 && !sender.running && Attention.count === 2 && Attention.toast === "New notification") {
                Attention.toastNotification.dismiss(); step = 4;
            } else if (step === 4 && Attention.count === 1 && Attention.toast === "") {
                Attention.clear(); step = 5;
            } else if (step === 5 && Attention.count === 0) {
                console.log("NOTIFICATIONS PASS: real D-Bus receipt, popup, history retention, quiet replacement, close and clear");
                stop(); Qt.quit();
            }
        }
    }
}
