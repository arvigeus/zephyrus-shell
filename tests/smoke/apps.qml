import QtQuick
import Quickshell
import "../../core"
import "../../shell"

Scope {
    QtObject {
        id: fixtureEntry
        property string name: "Fixture original name"
        property string genericName: "Editor"
        property var keywords: ["Fixture"]
        property var categories: ["Utility"]
        property string icon: ""
        property bool noDisplay: false
    }
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
                    if (!Modules.find("apps")) return;
                    ShellState.openModule("apps");
                    require(!find(overlay.item, "moduleContent").item, "Module loaded before drawer closed");
                    overlay.readyToLoad = true;
                    step++;
                } else if (step === 1) {
                    const loader = find(overlay.item, "moduleContent");
                    if (!loader || !loader.item || !loader.item.catalogReady || !loader.item.gpuChoicesReady) return;
                    apps = loader.item;
                    require(apps.applications.length > 0, "No fixture applications");
                    const search = find(apps, "appsSearchField");
                    require(search !== null, "Search field missing");
                    const all = apps.applications.length;
                    apps.category = "";
                    search.text = "";
                    require(apps.matches.length === all, "All applications missing");
                    search.text = "  NO SUCH ZEPHYRUS APPLICATION  ";
                    require(apps.matches.length === 0, "Unknown application matched");
                    search.text = "";
                    // Restore the initial tab before checking persisted favorites.
                    apps.category = Quickshell.env("APPS_TEST_PHASE") === "read" ? "favorites" : "";
                    apps.gpuChoices = [{id:"test-integrated", name:"Integrated"}, {id:"test-discrete", name:"Discrete"}];
                    const picker = find(apps, "app-gpu-picker-0");
                    if (!picker) return;
                    picker.clicked();
                    require(picker.menuOpen, "GPU picker did not open");
                    require(picker.parent.launchMenu && picker.parent.launchMenu.parent === picker.parent, "GPU menu is not owned by its application tile");
                    picker.clicked();
                    require(!picker.menuOpen, "Second click reopened GPU picker");
                    const id = apps.applications[0].id;
                    if (Quickshell.env("APPS_TEST_PHASE") === "write") {
                        require(apps.category === "", "Empty favorites should default to all applications");
                        require(!apps.isFavorite(id), "Test preferences are not isolated");
                        apps.toggleFavorite(id);
                        apps.category = "favorites";
                        require(apps.matches.some(app => app.id === id), "Added favorite not shown");
                        search.text = apps.applications[apps.applications.length - 1].name;
                        require(apps.matches.some(app => app.id === apps.applications[apps.applications.length - 1].id), "Search in Favorites did not include all installed apps");
                        search.text = "";
                    } else {
                        require(apps.category === "favorites", "Saved favorites should be the default");
                        require(apps.isFavorite(id), "Favorite did not survive restart");
                        apps.toggleFavorite(id);
                        require(!apps.isFavorite(id) && apps.matches.length === 0, "Favorite removal failed");
                    }
                    stop();
                    apps.category = "";
                    // Production DesktopEntry setters are not available here.
                    // Use a mutable QObject source in the same Main entry point.
                    apps.catalogueEntries = [fixtureEntry];
                    Qt.callLater(() => {
                        fixtureEntry.name = "Zephyrus renamed fixture";
                        search.text = "renamed fixture";
                        require(apps.matches.includes(fixtureEntry), "Metadata change did not refresh search index");
                        fixtureEntry.noDisplay = true;
                        Qt.callLater(() => {
                            require(!apps.applications.includes(fixtureEntry), "Hidden entry remained in catalogue");
                            fixtureEntry.noDisplay = false; search.text = "";
                            Qt.callLater(() => {
                                require(apps.applications.includes(fixtureEntry), "Restored entry did not return to catalogue");
                                ShellState.stopModule("apps");
                                require(overlay.item === null, "Overlay was retained after close");
                                console.log("APPS PASS", Quickshell.env("APPS_TEST_PHASE"), "loading gate, favorites, GPU picker toggle, metadata changes, destruction");
                                Qt.quit();
                            });
                        });
                    });
                }
            }
        }
    }
}
