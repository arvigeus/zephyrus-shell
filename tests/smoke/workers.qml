import QtQuick
import Quickshell
import "../../services"
import "../../modules/media"
import "../../modules/files" as Files

Scope {
    Files.FilesService {
        id: files
        startOnDemand: true
    }
    TorrentService { id: torrents }
    SubtitleService { id: subtitles }
    Worker { id: recovery; backend: "tests/fixtures/stopped-worker.py"; startOnDemand: true }
    Timer {
        interval: 100; repeat: true; running: true
        property int ticks: 0
        property int replies: 0
        property int phase: 0
        property int hiddenSerial: 0
        function pollTimer() { return torrents.data.find(child => child.objectName === "torrentJobPoll"); }
        function fail(message) { console.error("WORKER FAIL", message); Qt.quit(); }
        onTriggered: {
            if (++ticks > 80) { fail("Startup requests did not settle"); return; }
            if (phase === 0 && ticks > 4) {
                if (files.processReady || torrents.processReady || subtitles.processReady || files.pendingCount)
                    { fail("An unused worker started"); return; }
                phase = 1;
                files.request("list", {}, (result, failure) => {
                    if (failure || !result || !Array.isArray(result.entries)) { fail("Buffered read failed: " + failure); return; }
                    replies++;
                });
                files.request("unsupported", {}, (result, failure) => {
                    if (!failure) { fail("Invalid operation did not settle"); return; }
                    replies++;
                });
                torrents.request("local_list", {kind:"book"}, (result, failure) => {
                    if (failure || !Array.isArray(result)) { fail("On-demand worker failed: " + failure); return; }
                    replies++;
                });
            } else if (phase === 1 && replies === 3) {
                if (files.pendingCount || torrents.pendingCount || !files.processReady || !torrents.processReady || subtitles.processReady)
                    { fail("Unexpected worker lifetime or pending callbacks"); return; }
                phase = 2;
                recovery.request("list", {}, (result, failure) => {
                    if (!failure) { fail("Stopped worker did not fail its pending request"); return; }
                    replies++;
                });
            } else if (phase === 2 && recovery.stopped && replies === 4) {
                if (recovery.pendingCount) { fail("Stopped worker left pending callbacks"); return; }
                let settled = false;
                recovery.request("list", {}, (result, failure) => { settled = !!failure; });
                if (!settled || recovery.pendingCount) { fail("Request to a stopped worker did not fail immediately"); return; }
                torrents.monitorJobs = true;
                torrents.refreshJobs(); phase = 4;
            } else if (phase === 4 && !torrents.jobsLoading) {
                if (files.data.find(child => child.objectName === "filesEditPoll").running) { fail("Idle Files kept polling editing sessions"); return; }
                torrents.foreground = false;
                hiddenSerial = torrents.serial;
                phase = 5; ticks = 0;
            } else if (phase === 5 && ticks > 4) {
                if (pollTimer().running || torrents.serial !== hiddenSerial) { fail("Hidden idle module kept polling"); return; }
                torrents.jobs = [{id:"background", active:true}];
                if (!pollTimer().running) { fail("Hidden active job lost its monitor"); return; }
                torrents.jobs = [];
                torrents.foreground = true; phase = 6;
            } else if (phase === 6 && !torrents.jobsLoading) {
                if (!pollTimer().running || torrents.serial <= hiddenSerial) { fail("Returning did not refresh the monitor"); return; }
                console.log("WORKER PASS: lazy startup, buffered requests, stopped-worker failure, hidden idle suspension, background job monitoring and foreground refresh");
                Qt.quit();
            }
        }
    }
}
