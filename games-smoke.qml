import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1440
        implicitHeight: 960
        color: "#101115"
        ModuleLoader {
            id: overlay
            anchors.fill: parent
            readyToLoad: ShellState.panel === "module"
        }
        Timer {
            interval: 100
            running: true
            repeat: true
            property int step: 0
            property int attempts: 0
            property var games
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function require(value, message) {
                if (!value) {
                    console.error("GAMES FAIL", message);
                    Qt.quit();
                    throw new Error(message);
                }
            }
            onTriggered: {
                if (++attempts > 80) { require(false, "Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Modules.find("games")) return;
                    ShellState.openPlugin("games");
                    step++;
                } else if (step === 1) {
                    const loader = find(overlay, "moduleContent");
                    if (!loader || !loader.item) return;
                    games = loader.item;
                    require(games.objectName === "gamesBrowser", "Games entry point did not load");
                    require(!!find(games, "gamesCatalogueGrid"), "Games catalogue grid missing");
                    require(!!find(games, "gamesCatalogueRail"), "Games poster rail missing");
                    require(!!find(games, "discoverTab") && !!find(games, "favoritesTab"), "Games catalog tabs missing");
                    require(!!find(games, "gamesSearchButton") && !!find(games, "gamesFiltersButton"), "Games discovery controls missing");
                    step++;
                } else if (step === 2) {
                    if (games.initializing) return;
                    require(games.setupRequired, "Missing IGDB credentials did not show setup state");
                    require(games.catalogState.configured === false, "Unexpected catalog configuration state");
                    require(games.error === "", "Missing credentials became a fatal error: " + games.error);
                    ShellState.close();
                    require(!overlay.item, "Games overlay did not close");
                    console.log("GAMES PASS: entry point, setup fallback, worker startup, overlay destruction");
                    Qt.quit();
                }
            }
        }
    }
}
