import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 700
        ModuleLoader { id: overlay; anchors.fill: parent; readyToLoad: false }
        Timer {
            interval: 100; repeat: true; running: true
            property int step: 0
            property int attempts: 0
            property var apps
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const result = find(child, name);
                    if (result) return result;
                }
                return null;
            }
            function require(value, message) { if (!value) { console.error("APPS FAIL", message); Qt.quit(); throw new Error(message); } }
            onTriggered: {
                if (++attempts > 100) { require(false, "Loading timed out"); return; }
                if (step === 0) {
                    if (!Plugins.find("apps")) return;
                    ShellState.openPlugin("apps");
                    require(!find(overlay.item, "moduleContent").item, "Module loaded before drawer closed");
                    overlay.readyToLoad = true;
                    step++;
                } else if (step === 1) {
                    const loader = find(overlay.item, "moduleContent");
                    if (!loader || !loader.item || !loader.item.catalogReady || !loader.item.gpuChoicesReady) return;
                    apps = loader.item;
                    require(apps.applications.length > 0, "No fixture applications");
                    apps.gpuChoices = [{id:"test-integrated", name:"Integrated"}, {id:"test-discrete", name:"Discrete"}];
                    const picker = find(apps, "app-gpu-picker-0");
                    if (!picker) return;
                    picker.clicked();
                    require(picker.menuOpen, "GPU picker did not open");
                    picker.clicked();
                    require(!picker.menuOpen, "Second click reopened GPU picker");
                    const id = apps.applications[0].id;
                    if (Quickshell.env("APPS_TEST_PHASE") === "write") {
                        require(apps.category === "", "Empty favorites should default to all applications");
                        require(!apps.isFavorite(id), "Test preferences are not isolated");
                        apps.toggleFavorite(id);
                        apps.category = "favorites";
                        require(apps.matches.some(app => app.id === id), "Added favorite not shown");
                    } else {
                        require(apps.category === "favorites", "Saved favorites should be the default");
                        require(apps.isFavorite(id), "Favorite did not survive restart");
                        apps.toggleFavorite(id);
                        require(!apps.isFavorite(id) && apps.matches.length === 0, "Favorite removal failed");
                    }
                    ShellState.close();
                    require(overlay.item === null, "Overlay was retained after close");
                    console.log("APPS PASS", Quickshell.env("APPS_TEST_PHASE"), "loading gate, favorites, GPU picker toggle, destruction");
                    Qt.quit();
                }
            }
        }
    }
}
