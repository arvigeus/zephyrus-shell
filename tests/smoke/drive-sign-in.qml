import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../shell"

Scope {
    FloatingWindow {
        implicitWidth: 1200; implicitHeight: 780
        color: Theme.background
        ModuleLoader { id: overlay; anchors.fill: parent }
        FileView { id: callbackFixture; path: Quickshell.env("ZEPHYRUS_DRIVE_FIXTURE"); blockLoading: true }
        Timer {
            id: tester
            interval: 50; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var module: null
            property string firstJob: ""
            property string cancelledJob: ""
            property bool restartedFinished: false
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const result = find(child, name);
                    if (result) return result;
                }
                return null;
            }
            function content() { const loader = find(overlay.item, "moduleContent"); return loader ? loader.item : null; }
            function fail(message) { console.error("DRIVE SIGN IN FAIL", message); Qt.quit(); }
            function advance() { step++; ticks = 0; }
            onTriggered: {
                if (++ticks > 140) { fail("Timed out at step " + step + "; running=" + ShellState.runningModuleIds + "; active=" + (module ? module.activeWorkCount : -1) + "; jobs=" + (module ? JSON.stringify(module.fileWorker.jobs.map(j => ({state: j.state, error: j.error}))) : "destroyed")); return; }
                if (step === 0) {
                    if (!Modules.find("files")) return;
                    ShellState.openModule("files"); advance();
                } else if (step === 1) {
                    module = content();
                    if (!module || module.loading) return;
                    module.fileWorker.jobStartFailed.connect(message => tester.fail(message));
                    module.fileWorker.jobFinished.connect(job => {
                        if (job.state === "failed") { tester.fail(job.error); return; }
                        if (job.job_id !== tester.firstJob && job.job_id !== tester.cancelledJob && job.state === "finished") tester.restartedFinished = true;
                    });
                    module.switchProvider("gdrive"); advance();
                } else if (step === 2) {
                    if (module.loading) return;
                    if (!module.errorText || !module.driveNeedsSignIn) { fail("Isolated Drive should initially require sign-in"); return; }
                    const activity = module.activityCenter;
                    // Status messages use notifications; Activity is opened explicitly.
                    if (!activity.visible) { activity.showActivity(); return; }
                    const retry = find(activity.contentItem, "activityRetry");
                    if (!retry || !retry.visible || retry.text !== "Connect Google Drive") { fail("Folder retry did not offer Google sign-in"); return; }
                    retry.clicked();
                    advance();
                } else if (step === 3) {
                    const job = module.fileWorker.jobs.find(job => job.kind === "authorization" && job.state === "running");
                    if (!job) return;
                    firstJob = job.job_id;
                    const button = find(module, "connectGoogleDrive");
                    if (!button.enabled || button.text !== "Continue Google sign-in") { fail("Connect did not allow reopening sign-in"); return; }
                    const retry = find(module, "folderRetry");
                    if (retry.text !== "Continue Google sign-in") { fail("Folder retry did not offer to reopen sign-in"); return; }
                    retry.clicked(); advance();
                } else if (step === 4) {
                    const worker = module.fileWorker;
                    if (worker.startingJobs || ticks < 3) return;
                    if (worker.jobs.length !== 1 || worker.jobs[0].job_id !== firstJob) { fail("Reopening duplicated sign-in"); return; }
                    if (worker.jobs[0].state !== "finished" || module.loading || module.errorText) return;
                    if (module.entries[0].name !== "Connected fixture") { fail("Drive did not refresh after sign-in"); return; }
                    const activity = module.activityCenter;
                    activity.actionRequested(worker.jobs[0]); advance();
                } else if (step === 5) {
                    const job = module.fileWorker.jobs.find(job => job.job_id !== firstJob && job.state === "running");
                    if (!job || !job.kind) return;
                    cancelledJob = job.job_id;
                    module.finishDriveSignIn();
                    ShellState.showDesktop();
                    if (module.signInDialog.visible) { fail("Hidden Files left sign-in dialog open"); return; }
                    if (!ShellState.runningModuleIds.includes("files")) { fail("Desktop destroyed pending sign-in"); return; }
                    ShellState.openModule("files");
                    module.fileWorker.cancelJob(cancelledJob); advance();
                } else if (step === 6) {
                    const job = module.fileWorker.jobs.find(job => job.job_id === cancelledJob);
                    if (!job || job.state !== "cancelled") return;
                    if (module.driveSignInActive) { fail("Cancelled sign-in remained active"); return; }
                    find(module, "connectGoogleDrive").clicked(); advance();
                } else if (step === 7) {
                    const job = module.fileWorker.jobs.find(job => job.kind === "authorization" && job.state === "running");
                    if (!job) return;
                    callbackFixture.reload();
                    const attempt = JSON.parse(callbackFixture.text().trim() || "{}");
                    if (attempt.job_id !== job.job_id) return;
                    module.finishDriveSignIn();
                    const input = find(module.signInDialog.contentItem, "driveCallbackAddress");
                    input.text = attempt.callback;
                    module.submitDriveCallback();
                    if (input.text) { fail("Submitted callback was not cleared"); return; }
                    ShellState.showDesktop(); advance();
                } else if (step === 8) {
                    if (!restartedFinished) return;
                    if (!ShellState.runningModuleIds.includes("files")) { fail("Completion destroyed hidden Files"); return; }
                    module.host.close();
                    console.log("DRIVE SIGN IN PASS: real Files worker, loopback and manual callbacks, active Connect recovery, duplicate prevention, cancel/retry, popup dismissal, retention and hidden completion");
                    Qt.quit();
                }
            }
        }
    }
}
