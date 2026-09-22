import QtQuick
import Quickshell
import "core"
import "shell"
import "widgets"
ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 1440; implicitHeight: 1000
        color: "#101115"
        ModuleLoader { id: overlay; anchors.fill: parent; readyToLoad: ShellState.panel === "module" }
        CrossfadeImage { id: fadeProbe; width: 100; height: 100; opacity: 0; duration: 0 }
        Timer {
            interval: 300; running: true; repeat: true
            property int step: 0
            property int attempts: 0
            property var media
            property int pauseFrames: 0
            property var retainedCard
            property int retainedGeneration: 0
            property int settingsPhase: 0
            property int retainedRequests: 0
            property real retainedScroll: 0
            property int personPhase: 0
            property var toolbarGeometry
            function find(item,name) { if (item.objectName === name) return item; for (const child of item.children || []) { const found=find(child,name); if (found) return found; } return null; }
            function require(value, message) { if (!value) { console.error("MEDIA FAIL",message); Qt.quit(); throw new Error(message); } }
            onTriggered: {
                if (++attempts > 50) { require(false,"Timed out at step " + step); return; }
                if (step === 0) { if (!Plugins.find("movies")) return; ShellState.openPlugin("movies"); step++; }
                else if (step === 1) {
                    const loader=overlay.item.children.find(c=>c.objectName === "moduleContent");
                    if (!loader || !loader.item || loader.item.loading) return;
                    media=loader.item;
                    require(media.titles.length===20,"Catalogue did not load: " + media.error);
                    require(media.kind==="movie","Wrong module kind");
                    require(media.sameTitle({id:"tmdb:movie:42",tmdbId:42,kind:"movie"},{id:"tt42",tmdbId:42,imdbId:"tt42",kind:"movie"}),"Identity enrichment lost title ownership");
                    if (media.titleLoading || pauseFrames++ < 3) return;
                    require(media.nextPage === "fixture:2", "Pagination unavailable");
                    media.artworkLoading=true;
                    require(!media.detailLoading && media.titleLoading && find(media,"titleLoadingIndicator").running,"Indicator stopped before artwork finished");
                    media.artworkLoading=false;
                    ShellState.toggle("right");
                    require(ShellState.pluginId === "movies", "Settings discarded module");
                    ShellState.dismissPanel();
                    require(ShellState.panel === "module", "Settings did not restore module");
                    const backdrop = media.selected.backdrop;
                    media.artworkReady = true;
                    media.applyDetails({backdrop:"outdated",plot:"Updated synopsis"});
                    require(media.selected.backdrop === backdrop,"Details reverted artwork");
                    require(media.backgroundImage.toString() === backdrop,"Backdrop changed framing");
                    overlay.item.grabToImage(result=>result.saveToFile("tests/artifacts/media-rail.png"));
                    fadeProbe.source=media.selected.poster;
                    media.save({favorite:true,note:"Smoke note"}); step++;
                } else if (step === 2) {
                    if (!media.personal.favorite || !fadeProbe.hasImage) return;
                    fadeProbe.duration=1000; fadeProbe.source=media.selected.logo;
                    retainedCard=find(media,"catalogueGrid").currentItem;
                    retainedGeneration=media.selectionGeneration;
                    const rail=find(media,"catalogueRail");
                    rail.contentX=rail.originX + Math.max(0,rail.contentWidth-rail.width);
                    media.maybeLoadMore();
                    require(media.loading,"Rail did not request the next page at its end");
                    media.gridMode=true; step++;
                } else if (step === 3) {
                    if (media.loading || media.nextPage) return;
                    require(media.titles.length === 60 && !media.nextPage,"Grid did not automatically fill 60 titles");
                    const grid=find(media,"catalogueGrid");
                    require(grid.activeFocus,"Grid did not receive keyboard focus");
                    require(grid.currentItem === retainedCard,"Pagination recreated the existing poster delegate");
                    require(media.selectionGeneration === retainedGeneration,"Pagination reloaded the selected title");
                    media.updateCatalogue(media.titles.map(t => Object.assign({},t)),false);
                    require(grid.currentItem === retainedCard,"Identical snapshot recreated the existing poster delegate");
                    require(fadeProbe.transitioning,"Image transition did not start");
                    const images=fadeProbe.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
                    require(images.every(i => i.opacity > 0 && i.opacity < 1),"Old and new images did not crossfade together");
                    overlay.item.grabToImage(result=>result.saveToFile("tests/artifacts/media-grid.png"));
                    step++;
                } else if (step === 4) {
                    const grid=find(media,"catalogueGrid");
                    if (settingsPhase === 0) {
                        media.tab="cast";
                        grid.contentY=grid.cellHeight;
                        retainedScroll=grid.contentY;
                        retainedRequests=find(media,"mediaService").serial;
                        ShellState.toggle("right"); settingsPhase++; return;
                    }
                    const loader=find(overlay.item,"moduleContent");
                    require(loader.item === media,"Settings recreated module instance");
                    require(media.tab === "cast" && grid.contentY === retainedScroll,"Settings lost tab or scroll state");
                    require(find(media,"mediaService").serial === retainedRequests,"Settings triggered new provider requests");
                    if (settingsPhase === 1) { ShellState.dismissPanel(); settingsPhase++; return; }
                    ShellState.close();
                    require(!overlay.item,"Overlay not destroyed");
                    ShellState.openPlugin("series"); step++;
                } else if (step === 5) {
                    const loader=overlay.item.children.find(c=>c.objectName === "moduleContent");
                    if (!loader || !loader.item || loader.item.loading) return;
                    media=loader.item;
                    require(media.kind==="tv","Series module not separated");
                    require(media.gridMode,"TV series did not default to grid");
                    if (!media.seasons.length) return;
                    media.play(null);
                    require(media.tab === "episodes","Series provider did not open episode chooser"); pauseFrames=0; step++;
                } else if (step === 6) {
                    if (media.episodeLoading) return;
                    require(media.episodes.length===1,"Episode did not load");
                    require(!!find(media,"episodeRow"),"Clickable episode row missing");
                    if (pauseFrames++ === 0) {
                        overlay.item.grabToImage(result=>result.saveToFile("tests/artifacts/media-episodes.png"));
                        return;
                    }
                    const online=find(media,"onlineButton");
                    require(online.popup.count === 2,"Split button options missing");
                    media.filtersOpen=true;
                    const country=find(media,"countryPicker");
                    country.popup.open();
                    require(country.count > 200,"Country choices unavailable");
                    country.popup.close();
                    media.tab="cast"; online.popup.open(); step++;
                } else if (step === 7) {
                    const online=find(media,"onlineButton");
                    require(online.popup.visible && online.popup.width > 0,"Provider menu did not open");
                    online.popup.contentItem.grabToImage(result=>result.saveToFile("tests/artifacts/media-menu.png")); step++;
                } else if (step === 8) {
                    if (personPhase === 0) {
                        find(media,"onlineButton").popup.close();
                        media.searchOpen=true;
                        media.personDetails={name:"Fixture filmmaker",biography:"A person with acting and directing credits.",credits:[
                            {id:"older",kind:"tv",title:"Earlier work",year:2000,roles:["Actor"],poster:media.selected.poster},
                            {id:"newer",kind:"tv",title:"Recent work",year:2025,roles:["Actor","Director"],poster:media.selected.poster}]};
                        media.tab="person"; personPhase++; return;
                    }
                    const filmography=find(media,"filmography");
                    if (personPhase === 1) {
                        require(filmography.model[0].id === "newer","Filmography is not newest first");
                        require(media.personRoles.join(",") === "All,Actor,Director","Filmography roles missing");
                        const filters=find(media,"inlineFilters"), button=find(media,"filtersButton");
                        require(Math.abs(filters.mapToItem(media,0,filters.height/2).y-button.mapToItem(media,0,button.height/2).y)<2,"Filters are not inline");
                        overlay.item.grabToImage(result=>result.saveToFile("tests/artifacts/media-person-filters.png"));
                        toolbarGeometry=[find(media,"searchButton").x,find(media,"searchButton").y,button.x,button.y,find(media,"catalogueGrid").mapToItem(media,0,0).y];
                        media.personRole="Director"; personPhase++; return;
                    }
                    require(filmography.model.length === 1 && filmography.model[0].id === "newer","Filmography role filtering failed");
                    if (personPhase === 2) { media.searchOpen=false; media.filtersOpen=false; personPhase++; return; }
                    const searchButton=find(media,"searchButton"), filtersButton=find(media,"filtersButton");
                    const geometry=[searchButton.x,searchButton.y,filtersButton.x,filtersButton.y,find(media,"catalogueGrid").mapToItem(media,0,0).y];
                    require(geometry.every((value,index) => Math.abs(value-toolbarGeometry[index]) < 0.1),"Opening toolbar controls shifted buttons or content");
                    if (personPhase === 3) { searchButton.clicked(); personPhase++; return; }
                    if (personPhase === 4) { filtersButton.clicked(); personPhase++; return; }
                    ShellState.close();
                    console.log("MEDIA PASS: discovery, catalogue, details, favorites, grid, series episodes, destruction");
                    Qt.quit();
                }
            }
        }
    }
}
