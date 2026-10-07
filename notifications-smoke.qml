import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "attention"
import "widgets" as W

ShellRoot {
    id: root
    property int notificationId: 0
    property int cancelledCount: 0
    property bool retrySeen: false
    property var transientActivity: null
    readonly property string literalBody: "--literal $(command) <b>plain message</b>\nsecond line"
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    Component { id: activityFactory; W.OperationCenter { notificationTitle: "Transient module" } }
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
        implicitWidth: 800; implicitHeight: 500; color: "transparent"
        Item {
            id: surface
            anchors.fill: parent
            NotificationToast {
                id: toast
                width: 380; height: implicitHeight
                summary: Attention.toast
                body: Attention.toastNotification ? Attention.toastNotification.body : ""
                appName: Attention.toastNotification ? Attention.toastNotification.appName : ""
                onDismissed: Attention.dismissToast()
            }
            NotificationList { id: history; width: 380; height: 500; visible: false; cloudState: "ready"; view: "all" }
            W.OperationCenter {
                id: activity
                parent: surface
                notificationTitle: "Test module"
                onCancelRequested: root.cancelledCount++
                onActionRequested: job => root.retrySeen = job.job_id === "failed"
            }
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
                activity.notify(root.literalBody, true); step = 6;
            } else if (step === 6 && Attention.count === 1 && Attention.toastNotification) {
                if (activity.visible || Attention.toast !== "Test module" || Attention.toastNotification.body !== root.literalBody) { fail("Module message did not use desktop notifications literally"); return; }
                root.find(toast, "hideNotificationPopup").clicked();
                if (Attention.toast !== "" || Attention.count !== 1) { fail("Popup hide lost module notification history"); return; }
                history.visible = true; step = 7;
            } else if (step === 7 && ticks > 3) {
                const button = root.find(history, "dismissNotification:" + Attention.notifications.values[0].id);
                if (!button) return;
                button.clicked(); history.visible = false; step = 8;
            } else if (step === 8 && Attention.count === 0) {
                Attention.quiet = true;
                root.transientActivity = activityFactory.createObject(surface, {parent: surface});
                root.transientActivity.notify("Hidden module completed", false);
                root.transientActivity.destroy(); root.transientActivity = null; step = 9;
            } else if (step === 9 && Attention.count === 1) {
                if (Attention.toast || Attention.notifications.values[0].summary !== "Transient module") { fail("Quiet mode or history after module destruction failed"); return; }
                Attention.clear(); Attention.quiet = false;
                activity.jobs = [
                    {job_id:"failed", title:"Failed transfer", state:"failed", error:"Retryable failure", actionLabel:"Retry"},
                    {job_id:"finished", title:"Finished transfer", state:"finished", detail:"Completed"},
                    {job_id:"cancelled", title:"Cancelled transfer", state:"cancelled"},
                    {job_id:"running", title:"Active transfer", state:"running", done:50, total:100}
                ];
                activity.open(); ticks = 0; step = 11;
            } else if (step === 11 && ticks > 3) {
                const retry = root.find(activity.contentItem, "activityAction:failed");
                const dismiss = root.find(activity.contentItem, "dismissActivity:failed");
                if (!retry || !dismiss || !dismiss.visible) { fail("Failed transfer controls missing"); return; }
                step = -2;
                activity.contentItem.grabToImage(result => {
                    if (!result.saveToFile(Paths.file("tests/artifacts/activity-popup.png"))) { fail("Activity capture failed"); return; }
                    retry.clicked(); dismiss.clicked(); step = 12;
                });
            } else if (step === 12) {
                if (!root.retrySeen || root.cancelledCount || activity.shownJobs.length !== 3) { fail("Dismiss cancelled a job, removed retry, or kept failed row"); return; }
                activity.jobs = activity.jobs.map(job => Object.assign({}, job)); step = 13;
            } else if (step === 13) {
                if (activity.shownJobs.some(job => job.job_id === "failed")) { fail("Polling restored dismissed activity"); return; }
                root.find(activity.contentItem, "dismissFinishedActivity").clicked(); step = 14;
            } else if (step === 14) {
                if (activity.shownJobs.length !== 1 || activity.activeCount !== 1 || activity.jobs.length !== 4) { fail("Clearing history affected active transfers or source jobs"); return; }
                activity.dismissJob("running");
                if (activity.shownJobs.length !== 1) { fail("Active transfer was dismissible"); return; }
                root.find(activity.contentItem, "cancelActivity:running").clicked();
                if (root.cancelledCount !== 1) { fail("Cancel control did not cancel active transfer"); return; }
                activity.jobs = activity.jobs.map(job => job.job_id === "running" ? Object.assign({}, job, {state:"finished"}) : job); step = 15;
            } else if (step === 15) {
                const button = root.find(activity.contentItem, "dismissActivity:running");
                if (!button || !button.visible) return;
                button.clicked(); activity.close(); activity.open(); step = 16;
            } else if (step === 16) {
                if (activity.shownJobs.length) { fail("Reopening restored dismissed history"); return; }
                activity.jobs = activity.jobs.map(job => job.job_id === "failed" ? Object.assign({}, job, {state:"running"}) : job); step = 17;
            } else if (step === 17) {
                if (activity.shownJobs.length !== 1 || activity.shownJobs[0].job_id !== "failed") { fail("Reactivated work remained hidden"); return; }
                activity.close(); Attention.clear();
                console.log("NOTIFICATIONS PASS: real D-Bus receipt, popup, history, quiet replacement, module messages, literal arguments, module destruction, notification dismissal, transfer dismissal, retry and cancellation");
                stop(); Qt.quit();
            }
        }
    }
}
