import QtQuick
import Quickshell
import "core"
import "shell"
import "pictures"

ShellRoot {
    WallpaperRuntime {
        id: runtime
        monitors: [{name:"TEST", id:0, activeWorkspace:{id:1}}]
        clients: []
    }
    FloatingWindow {
        implicitWidth: 1440; implicitHeight: 900
        Backdrop { id: desktop; anchors.fill: parent }
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 100; repeat: true; running: true
            property int phase: 0
            property int ticks: 0
            property var first: ({})
            readonly property bool restoring: Quickshell.env("PICTURE_TEST_PHASE") === "restore"
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
            function fail(message) { console.error("PROVIDER FAIL", phase, message); Qt.quit(); }
            onTriggered: {
                if (++ticks > 220) { fail("Timed out"); return; }
                const pictures = content();
                if (phase === 0) {
                    if (restoring && !runtime.externalScreens.includes("TEST")) return;
                    ShellState.openPlugin("pictures"); phase = 1;
                } else if (phase === 1) {
                    if (!pictures || !pictures.providerCatalogReady) return;
                    if (restoring && pictures.providerId !== "fixture") { fail("Provider was not restored"); return; }
                    pictures.selectProvider("fixture"); phase = 2;
                } else if (phase === 2) {
                    if (pictures.loading) return;
                    if (pictures.error || pictures.selected.provider !== "fixture" || !pictures.videoSelected) {
                        fail("Catalogue: " + pictures.error); return;
                    }
                    first = pictures.selected;
                    if (restoring) {
                        pictures.browseGeneration++;
                        pictures.selectWallpaper({provider:"wallhaven", id:"fixture", path:"https://w.wallhaven.cc/full/fi/wallhaven-fixture.png"});
                        pictures.setDesktopWallpaper(); phase = 9; return;
                    }
                    if (pictures.page !== "opaque-next-page") { fail("Pagination token lost"); return; }
                    pictures.browse(true); phase = 3;
                } else if (phase === 3) {
                    if (pictures.loading) return;
                    if (pictures.wallpapers.length !== 2 || pictures.page !== 0) { fail("Pagination failed"); return; }
                    pictures.selectWallpaper(first);
                    pictures.toggleFavorite(); phase = 4;
                } else if (phase === 4) {
                    if (pictures.favoriteSaving) return;
                    if (!pictures.isFavorite(first)) { fail("Favorite failed"); return; }
                    pictures.setDesktopWallpaper(); phase = 5;
                } else if (phase === 5) {
                    if (pictures.settingWallpaper) return;
                    if (pictures.actionFailed || !runtime.externalScreens.includes("TEST")
                            || !desktop.wallpaperSource.toString().endsWith(".poster.jpg")) {
                        fail("Apply: " + pictures.actionMessage); return;
                    }
                    ShellState.stopPlugin("pictures"); phase = 6;
                } else if (phase === 6) {
                    if (content()) return;
                    if (!runtime.externalScreens.includes("TEST")) { fail("Playback lost on module close"); return; }
                    runtime.clients = [{monitor:0, workspace:{id:1}, fullscreen:2}]; phase = 7;
                } else if (phase === 7) {
                    if (++ticks < 45) return;
                    runtime.clients = []; phase = 8;
                } else if (phase === 8) {
                    if (++ticks < 55) return;
                    console.log("PROVIDER PASS catalogue, opaque pagination, favorites, Apply, module destruction, pause"); Qt.quit();
                } else if (phase === 9) {
                    if (pictures.settingWallpaper || runtime.stopping || runtime.pending) return;
                    if (runtime.animated || runtime.externalScreens.length || find(runtime, "wallpaperRuntimeWorker")
                            || pictures.actionFailed) { fail("Static cleanup: " + pictures.actionMessage); return; }
                    console.log("PROVIDER PASS restore, provider category, static replacement, owned cleanup"); Qt.quit();
                }
            }
        }
    }
}
