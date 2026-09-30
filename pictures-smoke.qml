import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1440; implicitHeight: 900
        Backdrop { id: desktop; anchors.fill: parent }
        Backdrop { id: otherDesktop; width: 320; height: 180; visible: false }
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 100; running: true; repeat: true
            property int phase: 0
            property int ticks: 0
            readonly property bool restoring: Quickshell.env("PICTURES_TEST_PHASE") === "read"
            readonly property string expected: "file://" + Quickshell.env("XDG_DATA_HOME") + "/zephyrus-shell/wallpapers/wallhaven-"
                + (restoring || phase >= 4 ? "fixture2" : "fixture") + ".png"
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function content() { return overlay.item ? find(overlay.item, "moduleContent") : null; }
            function fail(message) { console.error("PICTURES FAIL", message); Qt.quit(); }
            function pass() {
                console.log("PICTURES PASS", restoring ? "restore" : "set, errors, all desktops, module destruction");
                Qt.quit();
            }
            function desktopsReady() {
                return desktop.wallpaperSource.toString() === expected
                    && otherDesktop.wallpaperSource.toString() === expected
                    && find(desktop, "desktopWallpaperImage").displayedSource.toString() === expected;
            }
            onTriggered: {
                if (++ticks > 100) { fail("Timed out in phase " + phase); return; }
                if (restoring) { if (desktopsReady()) pass(); return; }
                if (phase === 0) {
                    if (!Plugins.find("pictures")) return;
                    if (desktop.wallpaperSource.toString()) { fail("Unexpected initial wallpaper"); return; }
                    ShellState.openPlugin("pictures"); phase = 1;
                } else if (phase === 1) {
                    const loader = content();
                    if (!loader || !loader.item) return;
                    const pictures = loader.item;
                    pictures.browseGeneration++;
                    pictures.loading = false;
                    pictures.selectWallpaper({provider:"wallhaven", id:"fixture", path:"https://w.wallhaven.cc/full/fi/wallhaven-fixture.png",
                        preview:Qt.resolvedUrl("assets/lucide/image.svg").toString(), width:1, height:1});
                    find(pictures, "setWallpaperButton").clicked();
                    if (!pictures.settingWallpaper) { fail("Wallpaper action did not start"); return; }
                    phase = 2;
                } else if (phase === 2) {
                    const pictures = content().item;
                    if (pictures.settingWallpaper || !desktopsReady()) return;
                    if (pictures.actionFailed || pictures.actionMessage !== "Wallpaper set using Zephyrus Shell. Lock screen updated.") {
                        fail("Wallpaper action failed: " + pictures.actionMessage); return;
                    }
                    // Invalid provider data must settle and leave the successful
                    // desktop choice intact, with the real action usable again.
                    pictures.selectWallpaper({provider:"wallhaven", id:"invalid", path:"", preview:""});
                    find(pictures, "setWallpaperButton").clicked();
                    phase = 3;
                } else if (phase === 3) {
                    const pictures = content().item;
                    if (pictures.settingWallpaper) return;
                    if (!pictures.actionFailed || !find(pictures, "setWallpaperButton").enabled || !desktopsReady()) {
                        fail("Failure did not restore action or preserve wallpaper"); return;
                    }
                    pictures.selectWallpaper({provider:"wallhaven", id:"fixture2", path:"https://w.wallhaven.cc/full/fi/wallhaven-fixture2.png",
                        preview:Qt.resolvedUrl("assets/lucide/image.svg").toString(), width:1, height:1});
                    find(pictures, "setWallpaperButton").clicked();
                    phase = 4;
                } else if (phase === 4) {
                    const pictures = content().item;
                    if (pictures.settingWallpaper || !desktopsReady()) return;
                    if (pictures.actionFailed) { fail("Retry failed: " + pictures.actionMessage); return; }
                    ShellState.close(); phase = 5;
                } else if (phase === 5 && !overlay.item) {
                    if (ShellState.runningPluginIds.includes("pictures") || !desktopsReady()) {
                        fail("Closing Pictures lost desktop wallpaper or retained its worker"); return;
                    }
                    pass();
                }
            }
        }
    }
}
