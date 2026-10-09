import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1200; implicitHeight: 780
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 50; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var module: null
            property var worker: null
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
            function fail(message) { console.error("FILE OPEN FAIL", message); Qt.quit(); }
            onTriggered: {
                if (++ticks > 250) { fail("Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Modules.find("files")) return;
                    ShellState.openPlugin("files"); step++; ticks = 0;
                } else if (step === 1) {
                    module = content();
                    if (!module || module.loading) return;
                    worker = module.fileWorker;
                    module.switchProvider("nextcloud"); step++; ticks = 0;
                } else if (step === 2) {
                    if (module.loading) return;
                    module.openEntry({path:"/Document.txt", name:"Document.txt", is_dir:false});
                    if (module.transferPicker.visible) { fail("Cloud open showed destination picker"); return; }
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 3) {
                    if (!ShellState.runningPluginIds.includes("files")) { fail("Desktop destroyed editing Files"); return; }
                    if (worker.jobs.some(j => j.state === "failed")) { fail(JSON.stringify(worker.jobs)); return; }
                    if (!worker.editSessions.length || !worker.jobs.some(j => j.title === "Save Document.txt" && j.state === "finished")) return;
                    if (worker.editSessions[0].error) { fail(worker.editSessions[0].error); return; }
                    module.activityCenter.actionRequested(worker.editSessions[0]);
                    step++; ticks = 0;
                } else if (step === 4) {
                    if (worker.editSessions.some(job => job.active)) return;
                    if (!ShellState.runningPluginIds.includes("files")) { fail("Stopping sync destroyed hidden Files"); return; }
                    module.host.close();
                    ShellState.openPlugin("files"); step++; ticks = 0;
                } else if (step === 5) {
                    module = content();
                    if (!module || module.loading) return;
                    worker = module.fileWorker;
                    module.switchProvider("nextcloud"); step++; ticks = 0;
                } else if (step === 6) {
                    if (module.loading) return;
                    module.openEntry({path:"/Document.txt", name:"Document.txt", is_dir:false});
                    step++; ticks = 0;
                } else if (step === 7) {
                    if (!worker.editSessions.length || !worker.jobs.some(j => j.title === "Open Document.txt" && j.state === "finished")) return;
                    if (ShellState.pluginId === "files") { fail("Opened editor left the shell overlay visible"); return; }
                    module.host.close();
                    if (ShellState.runningPluginIds.includes("files")) { fail("Explicit close kept editing module"); return; }
                    step++; ticks = 0;
                } else if (step === 8) {
                    ShellState.openPlugin("files"); step++; ticks = 0;
                } else if (step === 9) {
                    module = content();
                    if (!module || module.loading) return;
                    worker = module.fileWorker;
                    if (!worker.editSessions.length) return;
                    if (worker.editSessions[0].active) { fail("Recovered copy resumed without an action"); return; }
                    console.log("FILE OPEN PASS: real cloud Open, default app, atomic save-back, hidden retention, Stop syncing release, explicit close and durable recovery");
                    Qt.quit();
                }
            }
        }
    }
}
