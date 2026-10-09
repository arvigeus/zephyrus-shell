import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1920
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
            property bool libraryDefaultChecked: false
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
                    if (!Modules.find("games")) return;
                    ShellState.openPlugin("games");
                    step++;
                } else if (step === 1) {
                    const loader = find(overlay, item => item.objectName === "moduleContent");
                    if (!loader || !loader.item) return;
                    games = loader.item;
                    require(games.objectName === "gamesBrowser", "Games entry point did not load");
                    step++;
                } else if (step === 2) {
                    if (!libraryDefaultChecked) {
                        if (games.initializing || games.loading) return;
                        require(games.libraryMode && !games.localMode && games.titles.length === 2,
                                "Games with store games did not default to Library");
                        libraryDefaultChecked = true;
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
                    games.filtersOpen = true;
                    step++;
                } else if (step === 3) {
                    const filters = find(games, item => item.objectName === "gamesInlineFilters");
                    const favorites = find(games, item => item.objectName === "favoritesTab");
                    require(filters.visible && filters.mapToItem(games, 0, 0).x > favorites.mapToItem(games, favorites.width, 0).x + 100,
                            "Filters are not aligned to the right of the toolbar");
                    games.showLibrary();
                    step++;
                } else if (step === 4) {
                    if (games.loading || games.detailLoading || games.librariesLoading || !games.availability.stores.length) return;
                    require(games.libraryMode && games.titles.length === 2, "Store Library did not merge the shared game");
                    const shared = games.titles.find(game => game.title === "Smoke Game");
                    require(shared.libraryStores.length === 2 && shared.installedBy[0] === "steam", "Cross-store Library state is wrong");
                    require(games.selected.title === "Alan Wake II", "Library did not reuse the catalogue title");
                    const epic = games.availability.stores.find(store => store.store === "epic");
                    require(epic.primaryAction.id === "epic:install:AlanWake2", "Alan Wake II does not offer the owned Epic install");
                    require(!find(games, item => item.objectName === "gamesFiltersButton").enabled, "Catalogue filters are active in Library");
                    const choice = find(games, item => item.objectName === "gamesLibraryFilter");
                    choice.activated(1);
                    step++;
                } else if (step === 5) {
                    if (games.loading || games.detailLoading || games.compatibilityLoading) return;
                    require(games.libraryFilter === "installed" && games.titles.length === 1 && games.selected.title === "Smoke Game", "Installed Library filter is wrong");
                    find(games, item => item.objectName === "gamesLibraryFilter").activated(2);
                    step++;
                } else if (step === 6) {
                    if (games.loading) return;
                    require(games.libraryFilter === "owned" && games.titles.length === 2, "Purchased Library filter is wrong");
                    const search = find(games, item => item.objectName === "gamesSearchField");
                    search.text = "Alan Wake 2";
                    games.browse(false);
                    step++;
                } else if (step === 7) {
                    if (games.loading) return;
                    require(games.titles.length === 1 && games.titles[0].title === "Alan Wake II", "Library search did not match sequel numbering");
                    games.discover();
                    step++;
                } else if (step === 8) {
                    if (games.loading || games.detailLoading || games.compatibilityLoading || !games.availability.stores.length) return;
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
                } else if (step === 9) {
                    if (ShellState.pluginId || !screenshotReady) return;
                    require(ShellState.panel === "" && overlay.item && ShellState.runningPluginIds.includes("games"),
                            "Steam launch lost its module state");
                    games.host.close();
                    require(!overlay.item, "Explicit close did not release Games");
                    console.log("GAMES PASS: catalogue, details, ProtonDB identity, right-aligned filters, merged store Library, Installed/Purchased views, Alan Wake II Epic install, installed Steam Play action, retained state and explicit teardown");
                    Qt.quit();
                }
            }
        }
    }
}
