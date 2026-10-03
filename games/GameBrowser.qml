import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import "../core"
import "../widgets" as W
import "../widgets/Catalogue.js" as Catalogue
import "../media" as M

Item {
    id: root
    objectName: "gamesBrowser"
    property var host
    property url backgroundImage: ""
    property real backgroundImageOpacity: 0.2
    property int backgroundImageWidth: 1920
    property var titles: []
    property var selected: ({})
    property var availability: ({stores: [], diagnostics: ({})})
    property var compatibility: ({available: false, tier: "unknown", label: "Unavailable"})
    property var catalogState: ({configured: false, configPath: "", message: ""})
    property var libraries: ({})
    property var filters: ({genre:"", platform:"", sort:"-added", fromYear:"", toYear:""})
    property var genreOptions: []
    property var platformOptions: []
    property string error: ""
    property string detailError: ""
    property string notice: ""
    property bool initializing: true
    property bool loading: false
    property bool detailLoading: false
    property bool compatibilityLoading: false
    property bool librariesLoading: false
    property bool setupRequired: false
    property bool updatingCatalogue: false
    property bool favorites: false
    property bool localMode: false
    property var localFiles: []
    property bool torrentOpen: false
    property bool searchOpen: false
    property bool filtersOpen: false
    property bool filtersLoading: false
    property bool filtersLoaded: false
    property bool gridMode: false
    property bool searchHasFocus: false
    property int browseGeneration: 0
    property int selectionGeneration: 0
    property int nextOffset: 0
    property int matchGeneration: 0
    property string editingStore: ""
    property var pendingUninstall: ({})

    ListModel { id: catalogue }
    GameService { id: service; onFailed: message => root.error = message }
    M.TorrentService { id: localService }
    Settings {
        id: preferences
        location: "file://" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/zephyrus-shell/games-ui.ini"
    }

    readonly property bool hasNext: nextOffset > 0
    readonly property color protonDbColor: {
        const colors = {
            native: "#5daa4a", platinum: "#b8c9d9", gold: "#c9a227",
            silver: "#a7adb4", bronze: "#b87333", borked: "#b83a3a",
            pending: "#59616e", unknown: Theme.raised
        };
        return colors[String(compatibility.tier || "unknown").toLowerCase()] || Theme.raised;
    }
    readonly property url protonDbArtwork: {
        const tier = String(compatibility.tier || "unknown").toLowerCase();
        const ratingTiers = ["native", "platinum", "gold", "silver", "bronze", "borked"];
        return ratingTiers.indexOf(tier) >= 0
            ? Qt.resolvedUrl("../assets/protondb/react-protondb-" + tier + ".svg")
            : "";
    }
    readonly property string protonDbTooltip: {
        let detail = "ProtonDB · " + (compatibility.label || "Unknown");
        if (Number(compatibility.total || 0) > 0)
            detail += " · " + Number(compatibility.total) + (Number(compatibility.total) === 1 ? " report" : " reports");
        if (compatibility.warning)
            detail += "\n" + compatibility.warning;
        return detail;
    }

    function activate() { if (search.visible) search.forceActiveFocus(); else (gridMode ? grid : rail).forceActiveFocus(); }

    function backdropFor(game) {
        return ((game.artwork || [])[0] || (game.screenshots || [])[0] || game.cover || {}).url || "";
    }

    function sameGame(a, b) { return !!(a && b && a.id && b.id && a.id === b.id); }

    // Keep existing delegates alive while appending pages so decoded covers and scroll position stay put.
    function updateCatalogue(items, append) {
        updatingCatalogue = true;
        titles = Catalogue.update(catalogue, titles, items, append);
        updatingCatalogue = false;
    }

    function browse(append, forceRefresh) {
        if (localMode) {
            const generation = ++browseGeneration;
            loading = true; error = ""; nextOffset = 0; setupRequired = false;
            localService.request("local_list", {kind:"game"}, (result, failure) => {
                if (generation !== browseGeneration) return;
                loading = false;
                if (failure) { error = failure; return; }
                const query = search.text.trim().toLowerCase();
                updateCatalogue(result.filter(game => !query || game.title.toLowerCase().includes(query)), false);
                if (titles.length) { if (!titles.some(game => sameGame(game, selected))) selectGame(titles[0]); }
                else clearSelection();
            });
            return;
        }
        if (append && (loading || !hasNext)) return;
        const requestedOffset = append ? nextOffset : 0;
        const generation = ++browseGeneration;
        loading = true;
        error = "";
        notice = "";
        if (!append) nextOffset = 0;
        service.request("browse", {query:search.text, offset:requestedOffset, filters:filters, favorites:favorites, refresh:!!forceRefresh}, (result, failure) => {
            if (generation !== browseGeneration) return;
            loading = false;
            if (failure) { error = failure; return; }
            setupRequired = !!(result && result.setupRequired);
            if (!result) { error = "The catalogue returned no response."; return; }
            updateCatalogue(result.items || [], append);
            nextOffset = result.next === null || result.next === undefined ? 0 : Number(result.next);
            if (!append) { grid.positionViewAtBeginning(); rail.positionViewAtBeginning(); }
            if (result.warning) notice = result.warning;
            pagination.restart();
            if (!append) {
                if (titles.length) {
                    if (!titles.some(game => sameGame(game, selected))) selectGame(titles[0]);
                } else clearSelection();
            }
        });
    }

    function clearSelection() {
        ++selectionGeneration;
        selected = ({});
        availability = ({stores:[],diagnostics:({})});
        compatibility = ({available:false,tier:"unknown",label:"Unavailable"});
        backgroundImage = "";
        detailLoading = false;
        compatibilityLoading = false;
        detailError = "";
        notice = "";
    }

    function selectGame(game) {
        if (!game || !game.id || sameGame(game, selected)) return;
        const generation = ++selectionGeneration;
        selected = game;
        localFiles = []; torrentOpen = false;
        backgroundImage = backdropFor(game);
        availability = ({stores:[],diagnostics:({})});
        compatibility = ({available:false,tier:"unknown",label:"Unavailable"});
        detailLoading = true;
        compatibilityLoading = true;
        detailError = "";
        notice = "";
        editingStore = "";
        localService.request("local_files", {title:Object.assign({}, game, {kind:"game"})}, (result, failure) => {
            if (generation === selectionGeneration && !failure) localFiles = result;
        });
        detailDelay.restart();
    }

    function hydrateSelection(refresh) {
        if (!selected.id) return;
        if (localMode && selected.local) { detailLoading = false; compatibilityLoading = false; return; }
        const generation = selectionGeneration;
        const gameId = selected.id;
        detailLoading = true;
        service.request("details", {gameId:gameId, refresh:!!refresh}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            detailLoading = false;
            if (failure) { detailError = failure; return; }
            if (!result || !result.game) { detailError = "Game details are unavailable."; return; }
            applyGame(result.game);
            if (result.warning) detailError = result.warning;
        });
        service.request("availability", {gameId:gameId}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) detailError = failure;
            else if (result) availability = result;
        });
        service.request("protondb", {gameId:gameId}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            compatibilityLoading = false;
            if (failure) compatibility = ({available:false,tier:"unknown",label:"Unknown",warning:failure});
            else if (result) compatibility = result;
        });
    }

    function applyGame(game) {
        const patch = Object.assign({}, game);
        const backdrop = backdropFor(patch);
        if (backdrop) backgroundImage = backdrop;
        selected = Object.assign({}, selected, patch);
    }

    function refreshLibraries() {
        if (librariesLoading) return;
        librariesLoading = true;
        service.request("refresh_libraries", {}, (result, failure) => {
            librariesLoading = false;
            if (failure) { error = failure; return; }
            if (!result) return;
            libraries = result.libraries || ({});
            catalogState = result.catalog || catalogState;
            if (selected.id) refreshAvailability();
            if (!initializing) browse(false);
        });
    }

    function refreshAvailability() {
        const generation = selectionGeneration;
        service.request("availability", {gameId:selected.id}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) detailError = failure;
            else if (result) availability = result;
        });
    }

    function saveMatch(store, externalId) {
        const generation = ++matchGeneration;
        const selection = selectionGeneration;
        service.request("set_match", {gameId:selected.id,store:store,externalId:externalId}, (result, failure) => {
            if (selection !== selectionGeneration || generation !== matchGeneration) return;
            if (failure) { detailError = failure; return; }
            editingStore = "";
            notice = result && result.externalId ? "Store match saved." : "Manual store match cleared.";
            refreshAvailability();
            if (store === "steam") {
                compatibilityLoading = true;
                service.request("protondb", {gameId:selected.id}, (summary, compatibilityFailure) => {
                    if (selection !== selectionGeneration) return;
                    compatibilityLoading = false;
                    compatibility = compatibilityFailure ? ({available:false,tier:"unknown",label:"Unknown"}) : summary;
                });
            }
        });
    }

    function executeAction(actionId) {
        const generation = selectionGeneration;
        detailError = "";
        notice = "";
        service.request("action", {gameId:selected.id,actionId:actionId}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) detailError = failure;
            else if (result) {
                notice = result.message || "Action started.";
                if (result.started && host) host.close();
            }
        });
    }

    function requestUninstall(action) {
        if (!action || !action.id) return;
        pendingUninstall = action;
        uninstallConfirmation.open();
    }

    function openScreenshot(index) {
        const images = selected.screenshots || [];
        if (!images.length || index < 0 || index >= images.length) return;
        screenshotViewer.show(images, index, selected.title);
    }


    function maybeLoadMore() {
        if (loading || !hasNext) return;
        const nearEnd = gridMode
            ? grid.contentY + grid.height >= grid.contentHeight - grid.cellHeight * 2
            : rail.contentX + rail.width >= rail.contentWidth - rail.width * 0.5;
        if (nearEnd)
            browse(true);
    }

    function loadFilterOptions() {
        if (filtersLoading || filtersLoaded || !catalogState.configured) return;
        filtersLoading = true;
        service.request("catalog_filters", {}, (result, failure) => {
            filtersLoading = false;
            if (failure) { notice = "Game filters could not be loaded."; return; }
            genreOptions = result.genres || [];
            platformOptions = result.platforms || [];
            filtersLoaded = true;
        });
    }

    function saveFavorite(value) {
        const generation = selectionGeneration;
        service.request("set_favorite", {gameId:selected.id, favorite:value}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) { detailError = failure; return; }
            const isFavorite = !!(result && result.favorite);
            selected = Object.assign({}, selected, {favorite:isFavorite});
            updateCatalogue(titles.map(game => game.id === selected.id ? Object.assign({}, game, {favorite:isFavorite}) : game), false);
            if (favorites && !isFavorite) browse(false);
        });
    }

    function discover() {
        localMode = false;
        favorites = false;
        filtersOpen = false;
        searchDelay.stop();
        searchOpen = false;
        search.clear();
        searchDelay.stop();
        filters = {genre:"",platform:"",sort:"-added",fromYear:"",toYear:""};
        genreChoice.currentIndex = 0;
        platformChoice.currentIndex = 0;
        sortChoice.currentIndex = 0;
        fromYear.clear();
        toYear.clear();
        grid.currentIndex = 0;
        rail.currentIndex = 0;
        grid.positionViewAtBeginning();
        rail.positionViewAtBeginning();
        clearSelection();
        browse(false, true);
    }

    Component.onCompleted: {
        gridMode = preferences.value("catalogue/grid", false);
        service.request("init", {}, (result, failure) => {
            if (failure) error = failure;
            if (result) {
                catalogState = result.catalog || ({configured:false});
                libraries = result.libraries || ({});
                setupRequired = !catalogState.configured;
                refreshLibraries();
            }
            localService.request("local_list", {kind:"game"}, (local, localFailure) => {
                localMode = !localFailure && !!local && local.length > 0;
                initializing = false;
                if (!failure || localMode) browse(false);
            });
        });
    }

    Timer { id: detailDelay; interval: 80; onTriggered: root.hydrateSelection(false) }
    Timer { id: searchDelay; interval: 360; onTriggered: root.browse(false) }
    Timer { id: pagination; interval: 110; onTriggered: root.maybeLoadMore() }

    Dialog {
        id: uninstallConfirmation
        objectName: "gameUninstallConfirmation"
        parent: root
        x: Math.max(0, (root.width - width) / 2)
        y: Math.max(0, (root.height - height) / 2)
        width: Math.min(440, Math.max(300, root.width - 32))
        modal: true
        focus: true
        title: "Uninstall game?"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
        contentItem: ColumnLayout {
            spacing: 12
            W.Label {
                Layout.fillWidth: true
                text: "Uninstall " + (root.selected.title || "this game") + " through " + (root.pendingUninstall.store === "steam" ? "Steam" : "Epic Games Store") + "?"
                wrapMode: Text.Wrap
            }
            W.Label { Layout.fillWidth: true; text: "The launcher will remove its installed files."; color: Theme.muted; wrapMode: Text.Wrap }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                W.Action { text: "Cancel"; onClicked: uninstallConfirmation.close() }
                W.Action {
                    text: "Uninstall"
                    iconName: "trash-2"
                    destructive: true
                    onClicked: {
                        const actionId = root.pendingUninstall.id;
                        uninstallConfirmation.close();
                        root.executeAction(actionId);
                    }
                }
            }
        }
    }

    W.ImageGallery { id: screenshotViewer; objectName: "gameScreenshotViewer"; parent: root }

    W.DetailScrim {
        gridMode: root.gridMode
        opacity: root.backgroundImage.toString() ? 1 : 0
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            Layout.minimumHeight: 46
            Layout.maximumHeight: 46
            spacing: 8

            W.Action { iconName: "folder-open"; text: "Local"; highlighted: root.localMode; onClicked: { root.localMode = true; root.favorites = false; root.filtersOpen = false; root.browse(false); } }
            W.Action { objectName: "discoverTab"; iconName: "globe"; text: "Discover"; highlighted: !root.localMode && !root.favorites; onClicked: root.discover() }
            W.Action { objectName: "favoritesTab"; iconName: "star"; text: "Favorites"; highlighted: !root.localMode && root.favorites; onClicked: { root.localMode = false; root.favorites = true; root.filtersOpen = false; root.browse(false); } }
            Flickable {
                id: inlineFilters
                objectName: "gamesInlineFilters"
                visible: root.filtersOpen && !root.favorites && !root.localMode
                Layout.fillWidth: true
                Layout.preferredWidth: Math.min(filterFields.implicitWidth, root.width * 0.58)
                Layout.minimumWidth: 0
                Layout.preferredHeight: 46
                clip: true
                contentWidth: filterFields.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                W.WheelScroll { view: inlineFilters; horizontal: true }
                ScrollBar.horizontal: ScrollBar {}
                Row {
                    id: filterFields
                    spacing: 8
                    W.Choice { id: genreChoice; width: 142; model: [{id:"",name:"All genres"}].concat(root.genreOptions); textRole: "name"; Accessible.name: "Genre" }
                    W.Choice { id: platformChoice; width: 150; model: [{id:"",name:"All platforms"}].concat(root.platformOptions); textRole: "name"; Accessible.name: "Platform" }
                    W.Choice { id: sortChoice; width: 146; model: ["Popular","Newest releases","Highest rated","Recently updated","Alphabetical"]; Accessible.name: "Sort games" }
                    W.SearchField {
                        id: fromYear; width: 92; placeholderText: "From year"
                        validator: IntValidator { bottom: 1970; top: 2200 }
                        Accessible.name: "Release year from"
                    }
                    W.SearchField {
                        id: toYear; width: 92; placeholderText: "To year"
                        validator: IntValidator { bottom: 1970; top: 2200 }
                        Accessible.name: "Release year to"
                    }
                    W.Action {
                        text: "Apply"
                        onClicked: {
                            const sortValues = ["-added", "-released", "-rating", "-updated", "name"];
                            root.filters = {genre:genreChoice.currentIndex > 0 ? String(genreChoice.model[genreChoice.currentIndex].id) : "",
                                            platform:platformChoice.currentIndex > 0 ? String(platformChoice.model[platformChoice.currentIndex].id) : "",
                                            sort:sortValues[sortChoice.currentIndex] || "-added",
                                            fromYear:fromYear.text, toYear:toYear.text};
                            root.browse(false);
                        }
                    }
                    W.Action {
                        text: "Reset"
                        onClicked: {
                            genreChoice.currentIndex = 0; platformChoice.currentIndex = 0; sortChoice.currentIndex = 0;
                            fromYear.clear(); toYear.clear();
                            root.filters = {genre:"",platform:"",sort:"-added",fromYear:"",toYear:""};
                            root.browse(false);
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
            W.SearchField {
                id: search
                objectName: "gamesSearchField"
                visible: root.searchOpen
                Layout.preferredWidth: Math.min(Theme.catalogueSearchWidth, root.width * 0.30)
                Layout.minimumWidth: visible ? 150 : 0
                placeholderText: "Search games…"
                onTextChanged: searchDelay.restart()
                onAccepted: { searchDelay.stop(); root.browse(false); }
                Keys.onEscapePressed: { if (text.length) clear(); else focus = false; }
            }
            Item { Layout.minimumWidth: 28; Layout.maximumWidth: 28; Layout.preferredHeight: 28
                BusyIndicator { anchors.fill: parent; running: root.initializing || root.loading; visible: running }
            }
            W.IconButton { objectName: "gamesSearchButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; highlighted: root.searchOpen; iconName: "search"; text: "Search games"; onClicked: { root.searchOpen = !root.searchOpen; if (root.searchOpen) search.forceActiveFocus(); else { search.clear(); root.browse(false); } } }
            W.IconButton { objectName: "gamesFiltersButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; enabled: !root.favorites && !!root.catalogState.configured; highlighted: root.filtersOpen; iconName: "sliders-horizontal"; text: "Filters"; onClicked: { root.filtersOpen = !root.filtersOpen; if (root.filtersOpen) root.loadFilterOptions(); } }
            W.IconButton { objectName: "gamesGridButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; iconName: root.gridMode ? "panels-top-left" : "layout-grid"; text: root.gridMode ? "Show game rail" : "Show game grid"; onClicked: { root.gridMode = !root.gridMode; preferences.setValue("catalogue/grid", root.gridMode); } }
        }

        RowLayout {
            visible: !!root.error
            Layout.fillWidth: true
            W.Label { text: root.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
            W.Action { iconName: "refresh-cw"; text: "Retry"; onClicked: root.browse(false) }
        }

        W.Label {
            visible: !!root.notice && !root.error && !root.setupRequired
            Layout.fillWidth: true
            text: root.notice
            color: Theme.muted
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }

        Item {
            id: content
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid
                objectName: "gamesCatalogueGrid"
                x: 0
                width: parent.width * 0.51
                height: parent.height
                clip: true
                visible: root.gridMode && root.titles.length > 0
                model: catalogue
                cellWidth: width / Math.max(2, Math.floor(width / 160))
                cellHeight: cellWidth * 1.3 + 70
                keyNavigationEnabled: true
                keyNavigationWraps: false
                delegate: GameCard {
                    required property string payload
                    required property int index
                    readonly property var itemData: JSON.parse(payload)
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    game: itemData
                    selected: root.sameGame(root.selected, itemData)
                    installed: (itemData.installedBy || []).length > 0
                    onClicked: { grid.forceActiveFocus(); grid.currentIndex = index; root.selectGame(itemData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameGame(root.selected, currentItem.game)) root.selectGame(currentItem.game)
                Keys.onReturnPressed: if (currentItem) root.selectGame(currentItem.game)
                Keys.onEnterPressed: if (currentItem) root.selectGame(currentItem.game)
                W.WheelScroll { objectName: "gamesGridWheel"; view: grid; pixelsPerNotch: Math.max(360, grid.cellHeight * 1.2) }
                onContentYChanged: pagination.restart()
                ScrollBar.vertical: ScrollBar {}
            }

            ListView {
                id: rail
                objectName: "gamesCatalogueRail"
                visible: !root.gridMode && root.titles.length > 0
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.min(250, parent.height * 0.36)
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                model: catalogue
                keyNavigationEnabled: true
                keyNavigationWraps: false
                delegate: GameCard {
                    required property string payload
                    required property int index
                    readonly property var itemData: JSON.parse(payload)
                    width: Math.max(105, (rail.height - 82) / 1.25)
                    height: rail.height - 8
                    game: itemData
                    selected: root.sameGame(root.selected, itemData)
                    installed: (itemData.installedBy || []).length > 0
                    onClicked: { rail.forceActiveFocus(); rail.currentIndex = index; root.selectGame(itemData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameGame(root.selected, currentItem.game)) root.selectGame(currentItem.game)
                Keys.onReturnPressed: if (currentItem) root.selectGame(currentItem.game)
                Keys.onEnterPressed: if (currentItem) root.selectGame(currentItem.game)
                onContentXChanged: pagination.restart()
                W.WheelScroll { objectName: "gamesRailWheel"; view: rail; horizontal: true; pixelsPerNotch: 360 }
                ScrollBar.horizontal: ScrollBar {}
            }

            ColumnLayout {
                id: details
                x: root.gridMode ? parent.width * 0.55 : 16
                width: root.gridMode ? parent.width * 0.45 : Math.min(parent.width * 0.7, 1000)
                height: root.gridMode ? parent.height : parent.height - Math.min(270, parent.height * 0.36)
                visible: !!root.selected.id
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 142
                    spacing: 14
                    Rectangle {
                        Layout.preferredWidth: 102
                        Layout.preferredHeight: 136
                        color: Theme.surface
                        radius: 6
                        clip: true
                        W.CrossfadeImage {
                            id: gameDetailCover
                            anchors.fill: parent
                            anchors.margins: 3
                            source: root.selected.cover ? root.selected.cover.url : ""
                            fillMode: Image.PreserveAspectCrop
                            imageWidth: 420
                            resetOnSourceChange: true
                        }
                        W.Label {
                            anchors.centerIn: parent
                            width: parent.width - 10
                            text: root.selected.title || ""
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            visible: !gameDetailCover.hasImage
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 5
                        W.Label {
                            Layout.fillWidth: true
                            text: root.selected.title || ""
                            font.family: Theme.font; font.pixelSize: Theme.sp(Math.min(31, root.width / 43))
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }
                        W.Label {
                            Layout.fillWidth: true
                            id: gameMetadata
                            readonly property var allThemes: root.selected.themes || []
                            readonly property string themeSummary: allThemes.length
                                ? "Themes: " + allThemes.slice(0, 2).join(", ") + (allThemes.length > 2 ? " +" + (allThemes.length - 2) : "")
                                : ""
                            text: [root.selected.releaseDate ? root.selected.releaseDate.slice(0, 4) : "", (root.selected.genres || []).join(" / "), themeSummary].filter(Boolean).join("   ·   ")
                            color: Theme.muted
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            HoverHandler { id: metadataHover }
                            ToolTip.visible: metadataHover.hovered && gameMetadata.allThemes.length > 0
                            ToolTip.text: "Themes: " + gameMetadata.allThemes.join(" · ")
                        }
                        W.Label {
                            Layout.fillWidth: true
                            text: (root.selected.platforms || []).slice(0, 5).join(" · ")
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.sp(12)
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            W.IconButton {
                                iconName: root.selected.favorite ? "star-filled" : "star"
                                text: root.selected.favorite ? "Remove from favorites" : "Add to favorites"
                                onClicked: root.saveFavorite(!root.selected.favorite)
                            }
                            W.IconButton {
                                objectName: "officialGameWebsiteButton"
                                visible: !!root.selected.officialWebsite
                                iconName: "globe"
                                text: "Open official website"
                                onClicked: Browser.open(root.selected.officialWebsite, "games", "", root.host)
                            }
                            Button {
                                objectName: "protonDbButton"
                                visible: !!root.compatibility.url
                                implicitWidth: 42
                                implicitHeight: 42
                                hoverEnabled: true
                                Accessible.name: "Open ProtonDB compatibility page: " + (root.compatibility.label || "Unknown")
                                ToolTip.visible: hovered
                                ToolTip.text: root.protonDbTooltip
                                ToolTip.delay: 450
                                contentItem: W.AppIcon {
                                    anchors.centerIn: parent
                                    width: 34
                                    height: 34
                                    artwork: root.protonDbArtwork
                                    Accessible.ignored: true
                                }
                                background: Rectangle {
                                    radius: Theme.controlRadius
                                    color: root.protonDbColor
                                    border.color: parent.activeFocus ? Theme.text : "transparent"
                                    border.width: parent.activeFocus ? 2 : 0
                                }
                                onClicked: if (root.compatibility.url) Browser.open(root.compatibility.url, "games", "", root.host)
                            }
                            BusyIndicator {
                                visible: root.compatibilityLoading
                                running: visible
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                            }
                            W.IconButton {
                                iconName: "refresh-cw"
                                text: "Refresh game details"
                                enabled: !root.detailLoading
                                onClicked: root.hydrateSelection(true)
                            }
                            W.IconButton {
                                visible: root.localFiles.length > 0
                                iconName: "folder-open"
                                text: "Open local game files"
                                onClicked: {
                                    const path = root.localFiles[0].path;
                                    External.launch(["xdg-open", path.slice(0, path.lastIndexOf("/"))], root.host);
                                }
                            }
                            W.IconButton {
                                iconName: "search"
                                text: "Find"
                                highlighted: root.torrentOpen
                                onClicked: root.torrentOpen = !root.torrentOpen
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    RowLayout {
                        Layout.fillWidth: true
                        W.Label { text: "Stores"; font.family: Theme.font; font.pixelSize: Theme.sp(17); font.bold: true }
                        Item { Layout.fillWidth: true }
                        W.IconButton {
                            iconName: "refresh-cw"
                            text: root.librariesLoading ? "Refreshing local libraries" : "Refresh local libraries"
                            enabled: !root.librariesLoading
                            onClicked: root.refreshLibraries()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: root.availability.stores || []
                            delegate: Item {
                                id: storeButton
                                required property var modelData
                                readonly property var mainAction: modelData.primaryAction || ({type:"disabled",label:"Unavailable",enabled:false,tooltip:"Refresh store status."})
                                readonly property var uninstallAction: (modelData.actions || []).find(action => action.type === "uninstall") || ({})
                                readonly property color storeColor: modelData.store === "steam" ? "#1a9fff" : "#111111"
                                readonly property color actionColor: !mainAction.enabled ? Theme.surface
                                    : storeActionButton.down || storeMenu.down ? Qt.darker(storeColor, 1.15)
                                    : storeHover.hovered ? Qt.lighter(storeColor, 1.1) : storeColor
                                readonly property string tooltipText: {
                                    const status = modelData.statusTooltip || "";
                                    const reason = mainAction.tooltip || "";
                                    return reason && reason !== status ? [status, reason].filter(Boolean).join("\n") : status || reason;
                                }
                                Layout.fillWidth: true
                                implicitHeight: 42
                                HoverHandler { id: storeHover }
                                ToolTip.visible: storeHover.hovered && storeButton.tooltipText.length > 0
                                ToolTip.text: storeButton.tooltipText
                                ToolTip.delay: 450
                                Item {
                                    anchors.fill: parent
                                    Button {
                                        id: storeActionButton
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.right: storeMenu.visible ? storeMenu.left : parent.right
                                        anchors.rightMargin: 0
                                        text: storeButton.mainAction.label || "Unavailable"
                                        enabled: !!storeButton.mainAction.enabled
                                        hoverEnabled: true
                                        Accessible.name: storeButton.modelData.label + " " + text
                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 8
                                            W.AppIcon {
                                                Layout.preferredWidth: 23
                                                Layout.preferredHeight: 23
                                                artwork: Qt.resolvedUrl(storeButton.modelData.store === "steam" ? "../assets/stores/steam.svg" : "../assets/stores/epicgames.svg")
                                                Accessible.ignored: true
                                            }
                                            W.Label {
                                                Layout.fillWidth: true
                                                text: storeActionButton.text
                                                color: storeActionButton.enabled ? "#ffffff" : Theme.muted
                                                font.bold: true
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                        background: Rectangle {
                                            radius: 6
                                            topRightRadius: storeMenu.visible ? 0 : 6
                                            bottomRightRadius: storeMenu.visible ? 0 : 6
                                            color: storeButton.actionColor
                                            border.color: parent.activeFocus ? Theme.text : "transparent"
                                            border.width: parent.activeFocus ? 2 : 0
                                        }
                                        onClicked: {
                                            if (storeButton.mainAction.type === "link") {
                                                root.editingStore = storeButton.modelData.store;
                                                Qt.callLater(() => storeId.forceActiveFocus());
                                            } else if (storeButton.mainAction.type === "buy" && storeButton.mainAction.url)
                                                Browser.open(storeButton.mainAction.url, "games", "", root.host);
                                            else if (storeButton.mainAction.id) root.executeAction(storeButton.mainAction.id);
                                        }
                                    }
                                    W.IconButton {
                                        id: storeMenu
                                        visible: storeButton.modelData.availability === "available"
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 38
                                        iconName: "chevron-down"
                                        text: "More " + storeButton.modelData.label + " options"
                                        background: Rectangle {
                                            radius: 6
                                            topLeftRadius: 0
                                            bottomLeftRadius: 0
                                            color: storeButton.actionColor
                                            border.color: parent.activeFocus ? Theme.text : "transparent"
                                            border.width: parent.activeFocus ? 2 : 0
                                        }
                                        onClicked: storeOptions.visible ? storeOptions.close() : storeOptions.open()
                                        Menu {
                                            id: storeOptions
                                            popupType: Popup.Item
                                            y: parent.height
                                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                            width: 210
                                            background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
                                            MenuItem {
                                                text: "Open store page"
                                                visible: !!storeButton.modelData.storeUrl
                                                onTriggered: Browser.open(storeButton.modelData.storeUrl, "games", "", root.host)
                                            }
                                            MenuItem {
                                                text: "Edit store link"
                                                onTriggered: {
                                                    root.editingStore = storeButton.modelData.store;
                                                    Qt.callLater(() => storeId.forceActiveFocus());
                                                }
                                            }
                                            MenuSeparator { visible: !!storeButton.uninstallAction.id }
                                            MenuItem {
                                                text: "Uninstall…"
                                                visible: !!storeButton.uninstallAction.id
                                                onTriggered: root.requestUninstall(storeButton.uninstallAction)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        id: storeIdControls
                        readonly property var selectedStore: (root.availability.stores || []).find(store => store.store === root.editingStore) || ({})
                        visible: !!root.editingStore
                        Layout.fillWidth: true
                        spacing: 8
                        W.SearchField {
                            id: storeId
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            text: storeIdControls.selectedStore.externalId || ""
                            placeholderText: root.editingStore === "steam" ? "Steam AppID" : "Epic app ID"
                            Accessible.name: placeholderText
                            onAccepted: if (text.length > 0) root.saveMatch(root.editingStore, text)
                        }
                        W.Action {
                            iconName: "check"
                            text: "Save link"
                            enabled: storeId.text.length > 0
                            onClicked: root.saveMatch(root.editingStore, storeId.text)
                        }
                        W.Action {
                            visible: storeIdControls.selectedStore.matchSource === "override"
                            iconName: "trash-2"
                            text: "Clear match"
                            onClicked: root.saveMatch(root.editingStore, "")
                        }
                        W.Action {
                            iconName: "x"
                            text: "Cancel"
                            onClicked: root.editingStore = ""
                        }
                    }
                }

                W.Label {
                    visible: !!root.detailError
                    Layout.fillWidth: true
                    text: root.detailError
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
                W.Label {
                    visible: !!root.notice && !root.error && !root.setupRequired
                    Layout.fillWidth: true
                    text: root.notice
                    color: Theme.muted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }

                W.ScrollArea {
                    visible: !root.torrentOpen
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        spacing: 12
                        W.Label {
                            Layout.fillWidth: true
                            text: root.selected.summary || (root.detailLoading ? "Loading game details…" : "No description available.")
                            wrapMode: Text.Wrap
                            font.family: Theme.font; font.pixelSize: Theme.sp(15)
                        }
                        W.Label {
                            visible: (root.selected.developers || []).length > 0
                            Layout.fillWidth: true
                            text: "Developed by  " + (root.selected.developers || []).join(" · ")
                            color: Theme.muted
                            wrapMode: Text.Wrap
                        }
                        W.Label {
                            visible: (root.selected.publishers || []).length > 0
                            Layout.fillWidth: true
                            text: "Published by  " + (root.selected.publishers || []).join(" · ")
                            color: Theme.muted
                            wrapMode: Text.Wrap
                        }
                        W.Label {
                            visible: (root.selected.franchises || []).length + (root.selected.collections || []).length > 0
                            Layout.fillWidth: true
                            text: ["Series  " + (root.selected.franchises || []).join(" · "), "Collection  " + (root.selected.collections || []).join(" · ")].filter(value => !value.endsWith("  ")).join("   ·   ")
                            color: Theme.muted
                            wrapMode: Text.Wrap
                        }
                        ColumnLayout {
                            visible: (root.selected.screenshots || []).length > 0
                            Layout.fillWidth: true
                            spacing: 6
                            W.Label { text: "Screenshots"; color: Theme.muted }
                            W.ImageStrip {
                                objectName: "gamesScreenshotList"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 116
                                images: root.selected.screenshots || []
                                onActivated: index => root.openScreenshot(index)
                            }
                        }
                        ColumnLayout {
                            visible: (root.selected.relationships || []).length > 0
                            Layout.fillWidth: true
                            spacing: 4
                            W.Label { text: "Related games"; color: Theme.muted }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 5
                                Repeater {
                                    model: root.selected.relationships || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        height: 28
                                        width: relationText.implicitWidth + 16
                                        radius: 4
                                        color: Theme.surface
                                        W.Label {
                                            id: relationText
                                            anchors.centerIn: parent
                                            text: modelData.title + " · " + modelData.type
                                            font.family: Theme.font; font.pixelSize: Theme.sp(11)
                                            color: Theme.muted
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                M.TorrentSearch {
                    visible: root.torrentOpen
                    Layout.fillWidth: true; Layout.fillHeight: true
                    title: Object.assign({}, root.selected, {kind:"game",year:(root.selected.releaseDate || "").slice(0,4)})
                    onImported: {
                        localService.request("local_files", {title:Object.assign({}, root.selected, {kind:"game"})}, (result, failure) => { if (!failure) root.localFiles = result; });
                        if (root.localMode) root.browse(false);
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(560, parent.width - 64)
                visible: !root.localMode && !root.initializing && !root.loading && !root.titles.length && root.setupRequired && !root.error
                spacing: 12
                W.Label { text: "Set up the Games catalogue"; font.family: Theme.font; font.pixelSize: Theme.sp(24); font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                W.Label {
                    Layout.fillWidth: true
                    text: root.catalogState.configError
                        ? "Games could not read its configuration: " + root.catalogState.configError + "\n\nFix " + (root.catalogState.configPath || "~/.config/zephyrus-shell/games.json") + " and add a valid game catalogue API key. Steam discovery and launching, and ProtonDB links, remain available."
                        : "Create " + (root.catalogState.configPath || "~/.config/zephyrus-shell/games.json") + " and add a game catalogue API key. Steam discovery and ProtonDB links work without Legendary or UMU."
                    wrapMode: Text.Wrap
                    color: Theme.muted
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(480, parent.width - 64)
                visible: !root.initializing && !root.loading && !root.titles.length && (root.localMode || root.catalogState.configured) && !root.error && !root.setupRequired
                spacing: 8
                W.Label { Layout.fillWidth: true; text: root.localMode ? "No local game files yet." : root.favorites ? "No favorite games yet." : search.text ? "No games found." : "No catalogue results are available."; font.family: Theme.font; font.pixelSize: Theme.sp(20); horizontalAlignment: Text.AlignHCenter }
                W.Label { Layout.fillWidth: true; text: root.localMode ? "Find a local copy from a game in Discover." : root.favorites ? "Add a game to Favorites from its details." : "Try another title or refresh the catalogue."; color: Theme.muted; horizontalAlignment: Text.AlignHCenter }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.initializing && !root.titles.length
                BusyIndicator { running: parent.visible; Layout.alignment: Qt.AlignHCenter }
                W.Label { text: "Checking the local libraries…"; color: Theme.muted; Layout.alignment: Qt.AlignHCenter }
            }
        }
    }
}
