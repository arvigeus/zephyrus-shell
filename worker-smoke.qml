import QtQuick
import Quickshell
import "services"
import "media"

ShellRoot {
    Worker {
        id: files
        backend: "plugins/files/backend.py"
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
                recovery.backend = "plugins/files/backend.py";
                recovery.restart();
                phase = 3;
                recovery.request("list", {}, (result, failure) => {
                    if (failure || !result || !Array.isArray(result.entries)) { fail("Restarted worker did not recover: " + failure); return; }
                    replies++;
                });
            } else if (phase === 3 && replies === 5) {
                if (recovery.stopped || recovery.pendingCount || !recovery.processReady) { fail("Unexpected restarted worker state"); return; }
                console.log("WORKER PASS: unused services stay stopped, startup requests settle, callbacks release, stopped worker restarts and accepts requests");
                Qt.quit();
            }
        }
    }
}
