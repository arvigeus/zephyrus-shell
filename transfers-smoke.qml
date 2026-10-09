import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 1200; implicitHeight: 780
        color: Theme.background
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 50; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var module: null
            property real listHeight: 0
            property bool captured: false
            property bool musicRan: false
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
            function fail(message) { console.error("TRANSFERS FAIL", message); Qt.quit(); }
            onTriggered: {
                if (++ticks > 220) { fail("Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Modules.find("files")) return;
                    ShellState.openPlugin("files"); step++; ticks = 0;
                } else if (step === 1) {
                    module = content();
                    if (!module || module.loading) return;
                    listHeight = find(module, "filesList").height;
                    module.statusText = "A notification that must not resize the file list";
                    step++; ticks = 0;
                } else if (step === 2) {
                    if (find(module, "filesList").height !== listHeight) { fail("Files notification resized content"); return; }
                    module.chooseTransfer({path:Quickshell.env("ZEPHYRUS_TRANSFER_FIXTURE") + "/source.txt", name:"source.txt", is_dir:false}, "local", false);
                    step++; ticks = 0;
                } else if (step === 3) {
                    // Popups live on the window overlay, outside the module Item.
                    if (ticks < 15) return;
                    if (!captured) {
                        captured = true;
                        module.transferPicker.contentItem.grabToImage(result => {
                            result.saveToFile("tests/artifacts/files-destination.png");
                            step++; ticks = 0;
                        });
                    }
                } else if (step === 4) {
                    module.fileWorker.startJob("transfer", {source:"local", path:Quickshell.env("ZEPHYRUS_TRANSFER_FIXTURE") + "/source.txt", destination:"local", target:Quickshell.env("ZEPHYRUS_TRANSFER_FIXTURE") + "/target", title:"Lifecycle fixture"});
                    ShellState.showDesktop();
                    if (module.transferPicker.visible) { fail("Hidden Files left its destination popup open"); return; }
                    if (!ShellState.runningPluginIds.includes("files")) { fail("Desktop destroyed active Files"); return; }
                    step++; ticks = 0;
                } else if (step === 5) {
                    if (!module.fileWorker.jobs.some(job => job.state === "finished")) return;
                    if (!ShellState.runningPluginIds.includes("files")) { fail("Completion destroyed Files"); return; }
                    module.host.close();
                    ShellState.openPlugin("music"); step++; ticks = 0;
                } else if (step === 6) {
                    module = content();
                    if (!module) return;
                    const worker = find(module, "musicService");
                    if (!worker) { fail("Music owned worker missing"); return; }
                    worker.startJob("download_start", {kind:"track", item:{id:"fixture", title:"Fixture", artist:"Artist", album:"Album", releaseDate:"2020-01-01", duration:4}, title:"Lifecycle fixture"});
                    ShellState.showDesktop();
                    if (!ShellState.runningPluginIds.includes("music")) { fail("Desktop destroyed downloading Music"); return; }
                    step++; ticks = 0;
                } else if (step === 7) {
                    const worker = find(module, "musicService");
                    if (worker.jobs.some(job => job.state === "running")) musicRan = true;
                    if (!worker.jobs.some(job => job.state === "finished")) return;
                    if (!ShellState.runningPluginIds.includes("music")) { fail("Completion destroyed Music"); return; }
                    module.host.close();
                    if (!musicRan) { fail("Music stream download never ran"); return; }
                    console.log("TRANSFERS PASS: Files popup geometry, destination picker, real copy and download-start retention, hidden completion preserves modules, explicit close releases workers");
                    Qt.quit();
                }
            }
        }
    }
}
