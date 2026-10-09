import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "shell"
import "pictures"

ShellRoot {
    id: root
    property string fixtureAction: ""
    property bool fixtureDone: false
    function fixture(action) {
        fixtureDone = false;
        fixtureAction = action;
        fixtureControl.running = true;
    }
    Process {
        id: fixtureControl
        command: ["engine-fixture-control", root.fixtureAction]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) { console.error("ENGINE FAIL fixture action", root.fixtureAction); Qt.quit(); }
            root.fixtureDone = true;
        }
    }
    WallpaperRuntime {
        id: runtime
        monitors: [{name:"TEST", id:0, activeWorkspace:{id:1}}]
        clients: []
    }
    FileView {
        id: commands
        path: Quickshell.env("ENGINE_FIXTURE_ROOT") + "/commands.jsonl"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FloatingWindow {
        implicitWidth: 1440; implicitHeight: 900
        Backdrop { id: desktop; anchors.fill: parent }
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 100; repeat: true; running: true
            property int phase: 0
            property int ticks: 0
            readonly property bool restoring: Quickshell.env("ENGINE_TEST_PHASE") === "restore"
            readonly property bool staticRecovery: Quickshell.env("ENGINE_TEST_PHASE") === "static-recovery"
            property var installedFixture: ({})
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function content() {
                const loader = overlay.item ? find(overlay.item, "moduleContent") : null;
                return loader ? loader.item : null;
            }
            function fail(message) { console.error("ENGINE FAIL", phase, message); Qt.quit(); }
            function lastCommand() {
                commands.reload();
                try {
                    const lines = commands.text().trim().split("\n");
                    return JSON.parse(lines[lines.length - 1]).command;
                } catch (exception) { return ""; }
            }
            onTriggered: {
                if (++ticks > 250) { fail("Timed out"); return; }
                const pictures = content();
                if (phase === 0) {
                    if (staticRecovery) {
                        if (!runtime.configurationReady || !runtime.ownershipChecked || runtime.stopping
                                || runtime.pending || find(runtime, "wallpaperRuntimeWorker")) return;
                        if (runtime.animated || runtime.failed) { fail("Static orphan cleanup failed"); return; }
                        const expected = "file://" + Quickshell.env("XDG_DATA_HOME") + "/zephyrus-shell/wallpapers/wallhaven-fixture.png";
                        if (desktop.wallpaperSource.toString() !== expected) return;
                        console.log("ENGINE PASS static startup recovers orphan processes and unloads worker"); Qt.quit();
                        return;
                    }
                    if (restoring) {
                        if (!runtime.externalScreens.includes("TEST")) return;
                        ShellState.openPlugin("pictures"); phase = 7;
                        return;
                    }
                    if (runtime.animated || find(runtime, "wallpaperRuntimeWorker")) { fail("Idle worker exists"); return; }
                    ShellState.openPlugin("pictures"); phase = 1;
                } else if (phase === 1) {
                    if (!pictures || !pictures.providerCatalogReady) return;
                    pictures.selectProvider("wallpaper_engine"); phase = 2;
                } else if (phase === 2) {
                    if (pictures.loading) return;
                    if (pictures.selected.provider !== "wallpaper_engine") { fail("Catalogue failed: " + pictures.error); return; }
                    if (pictures.providerName("wallpaper_engine") !== "Wallpaper Engine") { fail("Provider name"); return; }
                    const fixture = pictures.wallpapers.find(item => item.id === "123456");
                    if (!fixture) { fail("Fixture missing from installed catalogue"); return; }
                    pictures.selectWallpaper(fixture);
                    find(pictures, "picturesEngineSourceChoice").activated(0); phase = 9;
                } else if (phase === 9) {
                    if (pictures.loading) return;
                    if (!pictures.error.includes("steam_api_key") || runtime.animated || find(runtime, "wallpaperRuntimeWorker")) {
                        fail("Workshop key setup / inactive playback"); return;
                    }
                    find(pictures, "picturesEngineSourceChoice").activated(1); phase = 10;
                } else if (phase === 10) {
                    if (pictures.loading) return;
                    if (pictures.error || !pictures.selected.installed) { fail("Installed catalogue recovery"); return; }
                    find(pictures, "openWorkshopButton").clicked(); phase = 11;
                } else if (phase === 11) {
                    if (pictures.openingWorkshop) return;
                    if (pictures.actionFailed || !pictures.actionMessage.includes("Subscribe") || runtime.animated) {
                        fail("Steam handoff failed or started renderer"); return;
                    }
                    pictures.selectWallpaper(Object.assign({}, pictures.selected, {
                        path:"file://" + Quickshell.env("ENGINE_FIXTURE_ROOT") + "/full-preview.png"})); phase = 12;
                } else if (phase === 12) {
                    if (find(pictures, "selectedWallpaperImage").displayedSource.toString() !== pictures.selected.path) return;
                    installedFixture = pictures.selected;
                    pictures.selectWallpaper(Object.assign({}, pictures.selected, {id:"999999", installed:false}));
                    phase = 15;
                } else if (phase === 15) {
                    if (!pictures.engineSetupMessage.includes("not downloaded")) return;
                    const warning = find(pictures, "wallpaperEngineSetupMessage");
                    if (!warning.visible || warning.color.toString() !== Theme.warning.toString()
                            || pictures.engineReady || runtime.animated) { fail("Missing requirement warning"); return; }
                    if (!find(pictures, "setWallpaperButton").enabled) { fail("Apply silently disabled"); return; }
                    find(pictures, "setWallpaperButton").clicked(); phase = 14;
                } else if (phase === 14) {
                    if (pictures.settingWallpaper) return;
                    if (!pictures.actionFailed || !pictures.actionMessage.includes("not downloaded")
                            || runtime.animated || find(runtime, "wallpaperRuntimeWorker")) {
                        fail("Missing download did not report a useful error"); return;
                    }
                    // A completed Steam download changes metadata for the same
                    // selected ID. Rechecking must update the Apply action too.
                    pictures.selectWallpaper(Object.assign({}, installedFixture, {installed:false}));
                    phase = 13;
                } else if (phase === 13) {
                    if (pictures.loading) return;
                    if (!pictures.selected.installed) return;
                    if (!pictures.engineReady) return;
                    if (pictures.engineSetupMessage) { fail("Completed setup warning did not clear"); return; }
                    if (!find(pictures, "setWallpaperButton").enabled) { fail("Downloaded wallpaper cannot be applied"); return; }
                    find(pictures, "setWallpaperButton").clicked(); phase = 3;
                } else if (phase === 3) {
                    if (pictures.settingWallpaper || !runtime.externalScreens.includes("TEST")) return;
                    if (pictures.actionFailed) { fail(pictures.actionMessage); return; }
                    ShellState.stopPlugin("pictures"); phase = 4;
                } else if (phase === 4) {
                    if (overlay.item) return;
                    if (!runtime.externalScreens.includes("TEST") || ShellState.runningPluginIds.includes("pictures")) {
                        fail("Playback did not outlive Pictures"); return;
                    }
                    root.fixture("hide"); phase = 16;
                } else if (phase === 16) {
                    if (!root.fixtureDone) return;
                    runtime.sync();
                    if (runtime.externalScreens.length) return;
                    if (runtime.failed) { fail("Temporary surface loss disabled playback"); return; }
                    root.fixture("show"); phase = 17;
                } else if (phase === 17) {
                    if (!root.fixtureDone) return;
                    runtime.sync();
                    if (!runtime.externalScreens.includes("TEST")) return;
                    root.fixture("crash"); phase = 18;
                } else if (phase === 18) {
                    if (!root.fixtureDone || !runtime.workerRestarts) return;
                    if (runtime.failed) { fail("Worker crash disabled playback"); return; }
                    phase = 19;
                } else if (phase === 19) {
                    if (!runtime.externalScreens.includes("TEST")) return;
                    if (runtime.workerRestarts !== 1) { fail("Unexpected restart count"); return; }
                    runtime.clients = [{monitor:0,workspace:{id:1},fullscreen:2,mapped:true}]; phase = 5;
                } else if (phase === 5) {
                    if (lastCommand() !== "pause") return;
                    runtime.clients = []; phase = 6;
                } else if (phase === 6) {
                    if (lastCommand() !== "play") return;
                    ShellState.openPlugin("pictures"); phase = 7;
                } else if (phase === 7) {
                    if (!pictures || !pictures.providerCatalogReady || pictures.loading) return;
                    if (pictures.providerId !== "wallpaper_engine"
                            || find(pictures, "picturesProviderChoice").currentIndex !== pictures.providerIndex("wallpaper_engine")
                            || pictures.filters.source !== "installed") {
                        fail("Reopened Pictures did not select the current wallpaper category"); return;
                    }
                    pictures.browseGeneration++;
                    pictures.loading = false;
                    pictures.selectWallpaper({provider:"wallhaven", id:"fixture",
                        path:"https://w.wallhaven.cc/full/fi/wallhaven-fixture.png"});
                    if (find(pictures, "wallpaperEngineSetupMessage").visible) { fail("Steam requirements shown for Wallhaven"); return; }
                    find(pictures, "setWallpaperButton").clicked(); phase = 8;
                } else if (phase === 8) {
                    if (pictures.settingWallpaper || runtime.animated || find(runtime, "wallpaperRuntimeWorker")) return;
                    if (pictures.actionFailed || runtime.externalScreens.length) { fail("Static shutdown failed"); return; }
                    const expected = "file://" + Quickshell.env("XDG_DATA_HOME") + "/zephyrus-shell/wallpapers/wallhaven-fixture.png";
                    if (desktop.wallpaperSource.toString() !== expected) return;
                    console.log("ENGINE PASS", restoring ? "startup restore, current category, teardown"
                        : "catalogue, Steam handoff, preview upgrade, installation refresh, apply, surface recovery, worker crash recovery, fullscreen, teardown"); Qt.quit();
                }
            }
        }
    }
}
