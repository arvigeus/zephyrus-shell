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
            property bool screenshotReady: false
            property bool localDefaultChecked: false
            property var games
            function find(item, predicate) {
                if (!item) return null;
                if (predicate(item)) return item;
                for (const child of item.children || []) {
                    const found = find(child, predicate);
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
                    if (!Plugins.find("games")) return;
                    ShellState.openPlugin("games");
                    step++;
                } else if (step === 1) {
                    const loader = find(overlay, item => item.objectName === "moduleContent");
                    if (!loader || !loader.item) return;
                    games = loader.item;
                    require(games.objectName === "gamesBrowser", "Games entry point did not load");
                    step++;
                } else if (step === 2) {
                    if (!localDefaultChecked) {
                        if (games.initializing || games.loading) return;
                        require(games.localMode && games.titles.length === 1, "Games with a local file did not open Local");
                        localDefaultChecked = true;
                        games.discover();
                        return;
                    }
                    if (games.initializing || games.loading || !games.titles.length || games.detailLoading || games.compatibilityLoading) return;
                    require(games.titles.length === 1 && games.selected.title === "Smoke Game", "Cached catalogue did not load");
                    require(games.selected.summary === "A local Games module smoke fixture.", "Game detail did not load");
                    require(games.selected.officialWebsite === "https://example.org/smoke-game", "Official website was lost");
                    require(!!find(games, item => item.objectName === "officialGameWebsiteButton" && item.visible), "Official website action is missing");
                    require(games.compatibility.url === "https://www.protondb.com/app/123", "ProtonDB identity link is wrong");
                    require(games.compatibility.tier === "gold", "Cached ProtonDB rating did not load");
                    require(String(games.backgroundImage).endsWith("games-cover.svg"), "Selected game art is not used as the background");
                    overlay.grabToImage(result => {
                        result.saveToFile("tests/artifacts/games.png");
                        screenshotReady = true;
                    });
                    const play = find(games, item => item.text === "Play" && typeof item.click === "function");
                    require(!!play, "Installed Steam Play action is missing");
                    const store = games.availability.stores.find(item => item.store === "steam");
                    require(store && store.installed && store.launchable, "Steam manifest was not recognized as installed and launchable");
                    play.click();
                    step++;
                } else if (step === 3) {
                    if (games.notice !== "Steam launch started." || !screenshotReady) return;
                    ShellState.close();
                    require(!overlay.item, "Games overlay did not close");
                    console.log("GAMES PASS: catalogue, details, ProtonDB identity, installed Steam Play action, overlay teardown");
                    Qt.quit();
                }
            }
        }
    }
}
