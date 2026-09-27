import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 1440; implicitHeight: 1000
        color: "#101115"
        ModuleLoader { id: overlay; anchors.fill: parent; readyToLoad: ShellState.panel === "module" }
        Timer {
            interval: 250; running: true; repeat: true
            property int step: 0
            property int attempts: 0
            property int screenshots: 0
            property bool localDefaultChecked: false
            property var browser
            function find(item, name) {
                if (item && item.objectName === name) return item;
                for (const child of item && item.children ? item.children : []) {
                    const found = find(child, name);
                    if (found) return found;
                }
                return null;
            }
            function require(value, message) {
                if (!value) { console.error("BOOKS FAIL", message); Qt.quit(); throw new Error(message); }
            }
            function screenshot(name) {
                overlay.grabToImage(result => {
                    if (!result.saveToFile("tests/artifacts/" + name)) {
                        console.error("BOOKS FAIL", "Could not save " + name);
                        Qt.quit();
                        return;
                    }
                    screenshots++;
                });
            }
            onTriggered: {
                if (++attempts > 80) { require(false, "Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Plugins.find("books")) return;
                    ShellState.openPlugin("books"); step++;
                } else if (step === 1) {
                    const content = find(overlay.item, "moduleContent");
                    if (!content || !content.item || content.status !== Loader.Ready || content.item.loading) return;
                    browser = content.item;
                    if (!localDefaultChecked) {
                        require(browser.localMode && browser.books.length === 1, "Books with a local file did not open Local");
                        localDefaultChecked = true;
                        browser.localMode = false;
                        browser.browse(false, false);
                        return;
                    }
                    if (browser.loading || browser.books.length !== 4) return;
                    require(String(browser.backgroundImage).length > 0, "Fixture book has no cover for the backdrop");
                    const backgroundBuffer = find(overlay.item, "imageA");
                    const hostBackdrop = backgroundBuffer ? backgroundBuffer.parent : null;
                    if (!hostBackdrop || String(hostBackdrop.displayedSource) !== String(browser.backgroundImage)) return;
                    require(hostBackdrop.imageOpacity > 0.99, "Shell background cover did not finish drawing");
                    require(hostBackdrop.imageWidth === 360, "Backdrop is not using the catalogue thumbnail decode size");
                    require(browser.objectName === "booksBrowser", "The real Books entry point did not open");
                    require(browser.books.length === 4, "Cached catalogue did not render: " + browser.error);
                    require(browser.selected.id === "OL100W", "Initial selection is not a Work record");
                    require(!browser.gridMode, "Smoke fixture did not start in the saved rail layout");
                    require(browser.selected.description === "A fixture synopsis for the selected work.", "Cached detail did not appear beside catalogue metadata");
                    require(String(browser.backgroundImage) === browser.selected.coverSmall, "Backdrop did not reuse the selected catalogue thumbnail");
                    require(find(browser, "openLibraryButton") && find(browser, "openLibraryButton").text === "Read on Open Library", "Reading action is not a single named icon button");
                    require(browser.editions.length === 0, "Editions were loaded before the tab was opened");
                    require(browser.nextPage === "", "Unexpected fixture pagination token");
                    screenshot("books-rail.png");
                    step++;
                } else if (step === 2) {
                    if (screenshots < 1) return;
                    find(browser, "layoutButton").clicked();
                    step++;
                } else if (step === 3) {
                    if (!find(browser, "catalogueGrid").visible) return;
                    screenshot("books-grid.png");
                    step++;
                } else if (step === 4) {
                    if (screenshots < 2) return;
                    const authorLink = find(browser, "authorLink-OL1A");
                    require(!!authorLink && authorLink.enabled, "Known author is not exposed as an enabled link");
                    authorLink.click();
                    step++;
                } else if (step === 5) {
                    if (browser.authorLoading || browser.authorWorks.length !== 1 || browser.authorDetails.name !== "Ada Lovelace") return;
                    require(browser.authorDetails.biography === "Fixture mathematician and writer.", "Author biography did not load from its cache");
                    require(browser.authorWorks[0].id === "OL200W", "Author works lost Work identity");
                    browser.tab = "overview";
                    browser.tab = "editions";
                    browser.loadEditions(false);
                    step++;
                } else if (step === 6) {
                    if (browser.editionsLoading || browser.editions.length !== 1) return;
                    require(browser.editions[0].id === "OL100M", "Edition rows lost Edition identity");
                    require(browser.editions[0].isbn[0] === "9780000000001", "Edition ISBN was not normalized");
                    browser.tab = "overview";
                    browser.saveFavorite(true);
                    step++;
                } else if (step === 7) {
                    if (!browser.personal.favorite) return;
                    browser.favorites = true;
                    browser.browse(false, false);
                    step++;
                } else if (step === 8) {
                    if (browser.loading) return;
                    require(browser.books.length === 1 && browser.books[0].id === "OL100W", "Favorite did not survive as a local Work record");
                    browser.searchOpen = true;
                    find(browser, "bookSearch").text = "no matching book";
                    step++;
                } else if (step === 9) {
                    if (browser.loading || browser.books.length !== 0) return;
                    require(browser.favorites, "Favorite search left the local Favorites view");
                    find(browser, "bookSearch").clear();
                    browser.searchOpen = false;
                    browser.favorites = false;
                    browser.browse(false, false);
                    step++;
                } else if (step === 10) {
                    if (browser.loading || browser.books.length !== 4) return;
                    require(browser.gridMode, "Grid layout state changed unexpectedly");
                    ShellState.close(); step++;
                } else {
                    const content = find(overlay.item, "moduleContent");
                    if (content && content.item) return;
                    console.log("BOOKS PASS: Open Library catalogue, Work identity, offline Favorites, author details, lazy editions, rail/grid layouts, module destruction");
                    Qt.quit();
                }
            }
        }
    }
}
