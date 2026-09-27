import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 1440; implicitHeight: 900
        color: Theme.background
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 100; running: true; repeat: true
            property var modules: ["projects", "files", "music", "radio", "pictures", "terminal"]
            property int index: 0
            property int phase: 0
            property int ticks: 0
            property double started: 0
            function content() {
                if (!overlay.item) return null;
                return overlay.item.children.find(c => c.objectName === "moduleContent") || null;
            }
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function fail(message) { console.error("MODULES FAIL", message); Qt.quit(); }
            onTriggered: {
                if (++ticks > 160) { fail("Timed out loading " + modules[index]); return; }
                if (phase === 0) {
                    if (!Plugins.find(modules[index])) return;
                    started = Date.now();
                    ShellState.openPlugin(modules[index]); phase = 1;
                } else if (phase === 1) {
                    const loader = content();
                    if (!loader) return;
                    if (loader.status === Loader.Error) { fail("Could not load " + modules[index]); return; }
                    if (!loader.item) return;
                    if (modules[index] === "pictures") {
                        const pictures = loader.item;
                        const preview = Qt.resolvedUrl("assets/lucide/film.svg").toString();
                        pictures.browseGeneration++;
                        pictures.selectWallpaper({provider:"wallhaven", id:"fixture",
                            thumbLarge:Qt.resolvedUrl("assets/lucide/image.svg").toString(),
                            preview:preview, path:Qt.resolvedUrl("assets/lucide/tv.svg").toString(),
                            width:1920, height:1080});
                        const image = find(pictures, "selectedWallpaperImage");
                        if (pictures.selectedPreviewSource.toString() !== preview || !image || !image.fadeInOnTop) {
                            fail("Pictures did not start from the uncropped preview"); return;
                        }
                    }
                    console.log("MODULE READY", modules[index], Date.now() - started, "ms");
                    phase = 2; ticks = 0;
                } else if (phase === 2 && ticks >= 20) {
                    if (modules[index] === "pictures") {
                        const pictures = content().item;
                        const full = Qt.resolvedUrl("assets/lucide/tv.svg").toString();
                        const preview = Qt.resolvedUrl("assets/lucide/film.svg").toString();
                        const expected = Math.ceil(pictures.fittedImageWidth() * 1.5) <= 960 ? preview : full;
                        const image = find(pictures, "selectedWallpaperImage");
                        if (pictures.selectedImageSource.toString() !== expected || image.displayedSource.toString() !== expected) {
                            fail("Pictures did not settle on the appropriate image resolution: width=" + pictures.fittedImageWidth()
                                + " selected=" + pictures.selectedImageSource + " displayed=" + image.displayedSource
                                + " expected=" + expected); return;
                        }
                    }
                    phase = 3;
                    overlay.grabToImage(result => {
                        result.saveToFile("tests/artifacts/module-" + modules[index] + ".png");
                        ShellState.close();
                    });
                } else if (phase === 3 && !overlay.item) {
                    index++; ticks = 0; phase = 0;
                    if (index === modules.length) { console.log("MODULES PASS: all entry points load and release their overlays"); Qt.quit(); }
                }
            }
        }
    }
}
