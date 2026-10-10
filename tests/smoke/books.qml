import QtQuick
import Quickshell
import "../../core"
import "../../shell"

Scope {
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
                if (++attempts > 100) { require(false, "Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Modules.find("books")) return;
                    ShellState.openModule("books"); step++;
                } else if (step === 1) {
                    const content = find(overlay.item, "moduleContent");
                    if (!content || !content.item || content.status !== Loader.Ready || content.item.loading) return;
                    browser = content.item;
                    if (!localDefaultChecked) {
                        require(browser.localMode && browser.books.length === 2, "Books with local files did not open Local");
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
                    require(!browser.offersChecked && browser.onlineOffers.length === 0, "Providers were searched while browsing");
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
                    if (browser.providerNames.length !== 1) return;
                    find(browser, "readOnlineButton").triggered(0);
                    step++;
                } else if (step === 11) {
                    if (browser.offersLoading) return;
                    require(browser.onlineOffers.length === 2, "Online offers did not preserve two formats: " + browser.offersError);
                    require(browser.onlineOffers[0].source === "provider" && browser.onlineOffers[0].match === "isbn", "Online offer lost its provider identity or exact ISBN match");
                    require(browser.selected.id === "OL100W" && browser.selected.authors[0].id === "OL1A", "Provider offer replaced Work or author identity");
                    const online = find(browser, "readOnlineButton");
                    require(online.options.length === 2 && online.popup.visible, "Multiple formats did not open the provider dropdown");
                    online.popup.close();
                    browser.tab = "torrent";
                    find(browser, "booksFind").find();
                    step++;
                } else if (step === 12) {
                    const lookup = find(browser, "booksFind");
                    if (browser.findOffersLoading || lookup.searching || lookup.results.length !== 1) return;
                    require(browser.findOffers.length === 2, "Find did not show provider formats: " + browser.findOffersError);
                    require(lookup.extraResults[0].size_bytes > 0 && lookup.extraResults[0].format === "epub", "Provider format or size is missing from Find");
                    require(lookup.results[0].source !== "provider" && !!lookup.results[0].url, "Torrent result lost its separate download identity");
                    const downloadButton = find(browser, "providerDownloadButton");
                    require(downloadButton && downloadButton.iconName === "download" && downloadButton.text.startsWith("Download "), "Provider Find action is not Download");
                    lookup.extraResultRequested(lookup.extraResults[1]);
                    step++;
                } else if (step === 13) {
                    if (!browser.downloadJobs.length) return;
                    ShellState.showDesktop();
                    require(ShellState.runningModuleIds.includes("books"), "Desktop destroyed the provider transfer");
                    step++;
                } else if (step === 14) {
                    if (browser.downloadJobs.some(job => ["queued", "running"].includes(job.state))) return;
                    require(ShellState.runningModuleIds.includes("books"), "Completion destroyed hidden Books");
                    browser.host.close();
                    ShellState.openModule("books");
                    step++;
                } else if (step === 15) {
                    const content = find(overlay.item, "moduleContent");
                    if (!content || !content.item || content.item.loading) return;
                    browser = content.item;
                    if (browser.selected.id !== "OL100W") { browser.selectBook(browser.books.find(book => book.id === "OL100W")); return; }
                    if (!browser.localFiles.some(file => file.path.endsWith("The Example Book (1843).pdf"))) return;
                    require(browser.localMode, "Downloaded provider book did not appear in Local");
                    require(browser.selected.id === "OL100W", "Exact ISBN download lost Work identity");
                    browser.selectBook(browser.books.find(book => book.source === "provider"));
                    require(!browser.workSelected && !browser.detailLoading && !browser.detailError, "Provider-only local record requested Work details");
                    require(!find(browser, "openLibraryButton").visible && !find(browser, "favoriteButton").visible && !find(browser, "editionsTab").visible, "Provider-only local record exposed Work operations");
                    require(browser.selected.description === "Standalone provider metadata.", "Provider-only local metadata was lost");
                    browser.localMode = false;
                    browser.browse(false, false);
                    step++;
                } else if (step === 16) {
                    if (browser.loading || browser.books.length !== 4) return;
                    browser.selectBook(browser.books[1]);
                    require(!browser.offersChecked && !browser.onlineOffers.length && !browser.findOffers.length, "Provider results survived a Work change");
                    browser.selectBook(browser.books[0]);
                    find(browser, "readOnlineButton").triggered(0);
                    browser.selectBook(browser.books[1]);
                    step++;
                } else if (step === 17) {
                    if (browser.detailLoading) return;
                    require(!browser.offersChecked && !browser.onlineOffers.length && browser.selected.id === "OL101W", "A late offer response changed the current selection");
                    browser.selectBook(browser.books[0]);
                    find(browser, "readOnlineButton").triggered(0);
                    step++;
                } else if (step === 18) {
                    if (browser.offersLoading) return;
                    require(browser.onlineOffers.length === 2, "Offers did not reload for the selected Work");
                    find(browser, "readOnlineButton").triggered(1);
                    step++;
                } else {
                    const content = find(overlay.item, "moduleContent");
                    if (content && content.item) return;
                    console.log("BOOKS PASS: Open Library catalogue, Work identity, offline Favorites, author details, lazy editions, rail/grid layouts, provider downloads, Desktop retention, provider-only Local records, deferred reading, stale selection, module destruction");
                    Qt.quit();
                }
            }
        }
    }
}
