import QtQuick
import Quickshell
import "../../core"
import "../../shell"

Scope {
    FloatingWindow {
        implicitWidth: 1200; implicitHeight: 900
        ModuleLoader { id: overlay; anchors.fill: parent; readyToLoad: ShellState.panel === "module" }
        Timer {
            interval: 200; running: true; repeat: true
            property int step: 0
            property int attempts: 0
            property var media
            property int closedFrames: 0
            function find(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function require(value, message) {
                if (!value) { console.error("DOWNLOAD FAIL", message); Qt.quit(); throw new Error(message); }
            }
            onTriggered: {
                if (++attempts > 110) { require(false, "Timed out at step " + step); return; }
                if (step === 0) { ShellState.openModule("movies"); step++; }
                else if (step === 1) {
                    if (!overlay.item || !overlay.item.currentModule || overlay.item.currentModule.loading) return;
                    media = overlay.item.currentModule;
                    if (!media.selected.id) return;
                    media.tab = "torrent";
                    const search = find(media, "torrentSearch");
                    search.commitQueue({url:"magnet:?xt=urn:btih:movie-fixture"}, null);
                    step++;
                } else if (step === 2) {
                    const worker = find(media, "torrentService");
                    if (worker.pendingDownloads || !worker.jobs.length) return;
                    require(worker.jobs[0].savePath.endsWith("/Movies/The Last Horizon (2025)"), "Movie destination is incorrect");
                    media.tab = "overview";
                    ShellState.showDesktop();
                    require(ShellState.runningModuleIds.includes("movies"), "Desktop destroyed active download monitor");
                    step++;
                } else if (step === 3) {
                    if (!find(media, "torrentService").jobs.some(job => job.status === "imported")) return;
                    require(ShellState.runningModuleIds.includes("movies"), "Completion destroyed hidden Movies");
                    media.host.close();
                    ShellState.openModule("movies"); step++;
                } else if (step === 4) {
                    if (!overlay.item || !overlay.item.currentModule || overlay.item.currentModule.loading) return;
                    media = overlay.item.currentModule;
                    if (!media.localFiles.length) return;
                    require(media.localMode, "Completed download did not appear in Local");
                    require(media.localFiles[0].path.endsWith("/Movies/The Last Horizon (2025)/The Last Horizon (2025).mkv"), "Movie was not organized");
                    ShellState.openModule("series"); step++;
                } else if (step === 5) {
                    if (!overlay.item || !overlay.item.currentModule || overlay.item.currentModule.kind !== "tv" || overlay.item.currentModule.loading) return;
                    media = overlay.item.currentModule;
                    media.localMode = false; media.browse(false); step++;
                } else if (step === 6) {
                    if (media.loading || !media.selected.id || media.titleLoading) return;
                    media.torrentEpisode = ({season:1, episode:1, episodeTitle:"The beginning"});
                    media.tab = "torrent";
                    find(media, "torrentSearch").commitQueue({url:"magnet:?xt=urn:btih:series-fixture"}, null);
                    step++;
                } else if (step === 7) {
                    const worker = find(media, "torrentService");
                    if (worker.pendingDownloads || !worker.jobs.length) return;
                    ShellState.stopModule("series");
                    require(!ShellState.runningModuleIds.includes("series"), "Explicit close retained series");
                    step++;
                } else if (step === 8) {
                    if (++closedFrames < 20) return;
                    ShellState.openModule("series"); step++;
                } else if (step === 9) {
                    if (!overlay.item || !overlay.item.currentModule || overlay.item.currentModule.loading) return;
                    media = overlay.item.currentModule;
                    const worker = find(media, "torrentService");
                    if (!worker.jobs.some(job => job.status === "imported")) return;
                    media.localMode = true; media.browse(false); step++;
                } else if (step === 10) {
                    if (media.loading || !media.localFiles.some(file => file.episodeTitle === "The beginning")) return;
                    const episode = media.localFiles.find(file => file.episodeTitle === "The beginning");
                    require(episode.path.endsWith("S01E01 - The beginning.mkv"), "Episode title is missing from filename");
                    ShellState.stopModule("series");
                    console.log("DOWNLOAD PASS: Find queue, title destination, Desktop retention, Local discovery, explicit close and resume, episode names");
                    Qt.quit();
                }
            }
        }
    }
}
