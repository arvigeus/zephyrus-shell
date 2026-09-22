import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 700
        Loader { id: overlay; anchors.fill: parent; sourceComponent: ModuleOverlay { readyToLoad: false } }
        Timer {
            interval: 100; repeat: true; running: true
            property int step: 0
            property int attempts: 0
            property var apps
            function require(value, message) { if (!value) { console.error("APPS FAIL", message); Qt.quit(); throw new Error(message); } }
            onTriggered: {
                if (++attempts > 100) { require(false, "Loading timed out"); return; }
                if (step === 0) {
                    ShellState.openPlugin("apps");
                    require(!overlay.item.loadStarted, "Module loaded before drawer closed");
                    overlay.item.readyToLoad = true;
                    step++;
                } else if (step === 1) {
                    const loader = overlay.item.children.find(child => child.objectName === "moduleContent");
                    if (!loader || !loader.item || !loader.item.catalogReady) return;
                    apps = loader.item;
                    require(apps.applications.length > 0, "No fixture applications");
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
                    overlay.active = false;
                    require(overlay.item === null, "Overlay was retained after close");
                    console.log("APPS PASS", Quickshell.env("APPS_TEST_PHASE"), "loading gate, favorites, destruction");
                    Qt.quit();
                }
            }
        }
    }
}
