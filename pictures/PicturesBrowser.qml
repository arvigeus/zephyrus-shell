import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../core"
import "../widgets" as W
import "../widgets/Catalogue.js" as Catalogue

Item {
    id: root
    property var host
    readonly property url backgroundImage: selectedPreviewSource
    property url selectedPreviewSource: ""
    property url selectedImageSource: ""
    property string imageSwapId: ""
    property var wallpapers: []
    property var selected: ({})
    property bool favoritesView: false
    property bool gridMode: false
    property bool searchOpen: false
    property bool filtersOpen: false
    property bool loading: true
    property bool randomLoading: false
    property bool settingWallpaper: false
    property bool favoriteSaving: false
    property string providerId: "wallhaven"
    property bool providerCatalogReady: false
    property var providerOptions: [
        {id:"wallhaven",name:"Wallhaven",random:true,search:true},
        {id:"bing",name:"Bing Daily",random:true,search:true}
    ]
    property string error: ""
    property string actionMessage: ""
    property bool actionFailed: false
    property string query: ""
    property int browseGeneration: 0
    property int favoriteGeneration: 0
    property int page: 0
    property var filters: ({categories:"111",sorting:"toplist",topRange:"1M",ratio:"",resolution:"",tagQuery:"",tagLabel:""})
    property var pendingFilters: ({categories:"111",sorting:"toplist",topRange:"1M",ratio:"",resolution:"",tagQuery:"",tagLabel:""})
    property var providerFilters: ({
        wallhaven:{categories:"111",sorting:"toplist",topRange:"1M",ratio:"",resolution:"",tagQuery:"",tagLabel:""},
        bing:{country:"US"}
    })
    property int tagSuggestionGeneration: 0
    property string tagSuggestionQuery: ""
    property var tagSuggestionResults: []
    property bool searchingTagSuggestions: false

    ListModel { id: catalogue }
    PicturesService { id: service; onFailed: message => root.error = message }

    Rectangle {
        x: -28; y: -80; width: root.width + 56; height: root.height + 108
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.scrim(0.925) }
            GradientStop { position: 0.58; color: Theme.scrim(0.800) }
            GradientStop { position: 1; color: Theme.scrim(0.925) }
        }
        opacity: root.backgroundImage.toString() ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    function isFavorite(value) {
        const key = typeof value === "string" ? value : wallpaperKey(value);
        return favoriteIds.has(key);
    }
    property var favoriteIds: new Set()

    function providerName(id) {
        const provider = providerOptions.find(value => value.id === id);
        return provider ? provider.name : id;
    }
    function providerDescriptor(id) { return providerOptions.find(value => value.id === id) || null; }
    function providerIndex(id) { return providerOptions.findIndex(value => value.id === id); }
    function providerSupports(id, capability) {
        const descriptor = providerDescriptor(id);
        return !!(descriptor && descriptor[capability]);
    }
    function syncFilterControls() {
        pendingFilters = Object.assign({}, filters);
    }
    function filterIndex(field) {
        const value = pendingFilters[field.key];
        const index = field.options.findIndex(option => option.value === value);
        return Math.max(0, index);
    }
    function filterVisible(field) {
        return !field.when || pendingFilters[field.when.key] === field.when.value;
    }
    function updatePendingFilter(key, value) {
        const next = Object.assign({}, pendingFilters);
        next[key] = value;
        pendingFilters = next;
    }
    function searchWallhavenTags(query) {
        const clean = String(query || "").trim().slice(0, 100);
        const generation = ++tagSuggestionGeneration;
        if (!clean) {
            tagSuggestionQuery = "";
            tagSuggestionResults = [];
            searchingTagSuggestions = false;
            return;
        }
        tagSuggestionQuery = clean.toLowerCase();
        tagSuggestionResults = [];
        searchingTagSuggestions = true;
        service.request("tagSearch", {query:clean}, (result, failure) => {
            if (generation !== tagSuggestionGeneration) return;
            searchingTagSuggestions = false;
            tagSuggestionResults = failure || !result ? [] : (result.tags || []);
        });
    }
    function selectProvider(id) {
        if (id === providerId || !providerDescriptor(id)) return;
        const stored = Object.assign({}, providerFilters);
        stored[providerId] = Object.assign({}, filters);
        providerFilters = stored;
        providerId = id;
        const descriptor = providerDescriptor(id);
        filters = Object.assign({}, providerFilters[id] || descriptor.defaultFilters || {});
        providerChoice.currentIndex = Math.max(0, providerIndex(id));
        syncFilterControls();
        query = "";
        search.text = "";
        searchDelay.stop();
        browse(false);
    }
    function loadProviders() {
        service.request("providers", {}, (result, failure) => {
            if (failure || !result || !Array.isArray(result.providers)) return;
            providerOptions = result.providers;
            providerCatalogReady = true;
            providerChoice.currentIndex = Math.max(0, providerIndex(providerId));
        });
    }

    function focusCatalogue() {
        const view = gridMode ? grid : rail;
        const index = wallpapers.findIndex(item => wallpaperKey(item) === wallpaperKey(selected));
        if (index >= 0) {
            view.currentIndex = index;
            if (gridMode) grid.positionViewAtIndex(index, GridView.Contain);
            else rail.positionViewAtIndex(index, ListView.Contain);
        }
        view.forceActiveFocus();
        pagination.restart();
    }
    function activate() { focusCatalogue(); }

    function wallpaperKey(item) { return item && item.id ? String(item.provider || "wallhaven") + ":" + String(item.id) : ""; }
    function updateCatalogue(items, append) {
        wallpapers = Catalogue.update(catalogue, wallpapers, items, append, wallpaperKey);
    }

    function selectWallpaper(item) {
        if (!item || !item.id) return;
        const changed = wallpaperKey(selected) !== wallpaperKey(item);
        selected = item;
        if (changed || !selectedImageSource.toString()) {
            if (changed) wallpaperPreview.clear();
            imageSwapId = wallpaperKey(item);
            // Wallhaven's large tile thumbnail may be cropped. Its original
            // preview keeps the image's aspect ratio in the detail pane.
            selectedPreviewSource = item.preview || item.path || item.thumbLarge || "";
            selectedImageSource = selectedPreviewSource;
            if (changed) wallpaperPreview.prepare();
        }
        actionMessage = "";
        actionFailed = false;
        const index = wallpapers.findIndex(value => wallpaperKey(value) === wallpaperKey(item));
        if (index >= 0) {
            if (gridMode) {
                grid.currentIndex = index;
                if (grid.visible) grid.positionViewAtIndex(index, GridView.Contain);
            } else {
                rail.currentIndex = index;
                if (rail.visible) rail.positionViewAtIndex(index, ListView.Contain);
            }
        }
    }

    function fittedImageWidth() {
        if (!selected.width || !selected.height || !wallpaperPreview.height) return wallpaperPreview.width;
        return Math.min(wallpaperPreview.width, wallpaperPreview.height * selected.width / selected.height);
    }

    function upgradeSelectedImage() {
        if (!selected.id || imageSwapId !== wallpaperKey(selected)
                || wallpaperPreview.displayedSource.toString() !== selectedPreviewSource.toString()) return;
        const targetWidth = Math.ceil(fittedImageWidth() * 1.5);
        const previewWidth = selected.preview === selected.thumbLarge ? 400 : 960;
        const preferred = targetWidth <= previewWidth
            ? (selected.preview || selected.path) : (selected.path || selected.preview);
        if (preferred && preferred !== selectedImageSource.toString()) selectedImageSource = preferred;
    }

    function browse(append) {
        if (append && (loading || !page || favoritesView)) return;
        const generation = ++browseGeneration;
        const requestedPage = append ? page : 1;
        loading = true;
        error = "";
        service.request("browse", {
            favorites:favoritesView,
            provider:providerId,
            query:query,
            page:requestedPage,
            filters:filters
        }, (result, failure) => {
            if (generation !== browseGeneration) return;
            loading = false;
            if (failure) { error = failure; return; }
            updateCatalogue(result.items || [], append);
            page = favoritesView ? 0 : Number(result.next || 0);
            if (!append) {
                if (wallpapers.length) {
                    if (!wallpapers.some(item => wallpaperKey(item) === wallpaperKey(selected))) selectWallpaper(wallpapers[0]);
                } else {
                            selected = ({});
                    selectedPreviewSource = "";
                    selectedImageSource = "";
                    imageSwapId = "";
                    actionMessage = "";
                }
            }
            pagination.restart();
        });
    }

    function chooseRandom() {
        if (randomLoading) return;
        if (favoritesView) {
            favoritesView = false;
            browse(false);
        }
        randomLoading = true;
        actionMessage = "";
        actionFailed = false;
        service.request("random", {provider:providerId,query:query,filters:filters}, (result, failure) => {
            randomLoading = false;
            if (failure) { error = failure; return; }
            const item = result && result.wallpaper;
            if (!item) { error = providerName(providerId) + " did not return a random image."; return; }
            updateCatalogue([item], true);
            selectWallpaper(item);
        });
    }

    function toggleFavorite() {
        if (!selected || !selected.id || favoriteSaving) return;
        const wallpaper = selected;
        const wallpaperId = wallpaperKey(wallpaper);
        const generation = ++favoriteGeneration;
        const value = !isFavorite(wallpaperId);
        favoriteSaving = true;
        service.request("favorite", {wallpaper:wallpaper,favorite:value}, (result, failure) => {
            if (generation !== favoriteGeneration) return;
            favoriteSaving = false;
            if (failure) { actionMessage = failure; actionFailed = true; return; }
            const next = new Set(favoriteIds);
            if (value) next.add(wallpaperId); else next.delete(wallpaperId);
            favoriteIds = next;
            actionFailed = false;
            actionMessage = value ? "Added to Favorites." : "Removed from Favorites.";
            if (favoritesView) browse(false);
        });
    }

    function setDesktopWallpaper() {
        if (!selected || !selected.id || settingWallpaper) return;
        const wallpaper = selected;
        settingWallpaper = true;
        actionMessage = "Downloading wallpaper…";
        actionFailed = false;
        service.request("set", {wallpaper:wallpaper}, (result, failure) => {
            settingWallpaper = false;
            actionMessage = failure || (result ? result.message : "Wallpaper could not be set.");
            actionFailed = !!failure;
        });
    }

    function applyFilters() {
        filters = Object.assign({}, pendingFilters);
        const stored = Object.assign({}, providerFilters);
        stored[providerId] = Object.assign({}, filters);
        providerFilters = stored;
        browse(false);
    }

    function resetFilters() {
        const descriptor = providerDescriptor(providerId);
        filters = Object.assign({}, descriptor ? descriptor.defaultFilters : {});
        const stored = Object.assign({}, providerFilters);
        stored[providerId] = Object.assign({}, filters);
        providerFilters = stored;
        syncFilterControls();
        browse(false);
    }

    function loadFavoriteIds() {
        service.request("browse", {favorites:true,query:"",page:1}, (result, failure) => {
            if (failure) { error = failure; return; }
            favoriteIds = new Set((result.items || []).map(item => wallpaperKey(item)));
        });
    }

    Component.onCompleted: {
        loadFavoriteIds();
        loadProviders();
        browse(false);
    }

    Timer { id: searchDelay; interval: 350; onTriggered: root.browse(false) }
    Timer { id: pagination; interval: 100; onTriggered: {
        if (root.favoritesView || root.loading || !root.page || !root.wallpapers.length) return;
        const nearEnd = root.gridMode
            ? grid.contentY + grid.height >= grid.contentHeight - grid.cellHeight * 2
            : rail.contentX + rail.width >= rail.contentWidth - rail.width * 0.55;
        if (nearEnd) root.browse(true);
    } }

    W.ImageGallery { id: gallery; parent: root }

    Component {
        id: choiceFilter
        W.Choice {
            property var definition: null
            width: definition ? definition.width || 150 : 150
            model: definition ? definition.options.map(option => option.label) : []
            currentIndex: definition ? root.filterIndex(definition) : 0
            Accessible.name: definition ? definition.label : ""
            onActivated: index => {
                if (definition) root.updatePendingFilter(definition.key, definition.options[index].value);
            }
        }
    }

    Component {
        id: tagsFilter
        PicturesTagPicker {
            property var definition: null
            width: definition ? definition.width || 220 : 220
            placeholderText: definition ? definition.placeholder || definition.label : "Search tags…"
            emptyText: definition ? definition.label : "Any tag"
            options: definition ? definition.options : []
            value: definition ? root.pendingFilters[definition.key] || "" : ""
            selectedLabel: definition ? root.pendingFilters.tagLabel || "" : ""
            searchResults: root.tagSuggestionResults
            searchResultsQuery: root.tagSuggestionQuery
            searching: root.searchingTagSuggestions
            onValueChosen: (value, label) => {
                if (!definition) return;
                root.updatePendingFilter(definition.key, value);
                root.updatePendingFilter("tagLabel", value ? label : "");
            }
            onTagSearchRequested: query => root.searchWallhavenTags(query)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 46
            Layout.preferredHeight: 46
            Layout.maximumHeight: 46
            spacing: 8

            W.Action {
                iconName: "globe"
                text: "Discover"
                highlighted: !root.favoritesView
                onClicked: { root.favoritesView = false; root.browse(false); }
            }
            W.Action {
                iconName: "star"
                text: "Favorites"
                highlighted: root.favoritesView
                onClicked: { root.favoritesView = true; root.browse(false); }
            }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
            Flickable {
                id: filterFieldsView
                objectName: "inlinePicturesFilters"
                visible: root.filtersOpen && !root.favoritesView
                Layout.fillWidth: true
                Layout.preferredWidth: filterFields.implicitWidth
                Layout.minimumWidth: 120
                Layout.maximumWidth: filterFields.implicitWidth
                Layout.preferredHeight: 46
                clip: true
                contentWidth: filterFields.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                W.WheelScroll { view: filterFieldsView; horizontal: true }
                ScrollBar.horizontal: ScrollBar {}
                Row {
                    id: filterFields
                    spacing: 8
                    Repeater {
                        model: root.providerDescriptor(root.providerId) ? root.providerDescriptor(root.providerId).filters : []
                        delegate: Loader {
                            required property var modelData
                            width: modelData.width || 150
                            visible: root.filterVisible(modelData)
                            height: 46
                            sourceComponent: modelData.type === "tags" ? tagsFilter : choiceFilter
                            onLoaded: item.definition = modelData
                        }
                    }
                    W.Action { text: "Apply"; onClicked: root.applyFilters() }
                    W.Action { text: "Reset"; onClicked: root.resetFilters() }
                }
            }
            W.SearchField {
                id: search
                visible: root.searchOpen
                Layout.preferredWidth: Math.min(Theme.catalogueSearchWidth, root.width * 0.30)
                placeholderText: root.favoritesView ? "Search favorites…" : "Search " + root.providerName(root.providerId) + "…"
                onTextChanged: { root.query = text; searchDelay.restart(); }
                onAccepted: { searchDelay.stop(); root.query = text; root.browse(false); }
                W.IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36
                    visible: search.text.length > 0
                    iconName: "x"
                    text: "Clear search"
                    onClicked: { search.clear(); search.forceActiveFocus(); }
                }
            }
            Item {
                Layout.minimumWidth: 28
                Layout.maximumWidth: 28
                Layout.preferredHeight: 28
                BusyIndicator { anchors.fill: parent; running: root.loading || root.randomLoading; visible: running }
            }
            W.IconButton {
                objectName: "picturesSearchButton"
                iconName: "search"
                text: "Search wallpapers"
                visible: root.favoritesView || root.providerSupports(root.providerId, "search")
                highlighted: root.searchOpen
                onClicked: {
                    root.searchOpen = !root.searchOpen;
                    if (root.searchOpen) search.forceActiveFocus(); else { search.text = ""; root.query = ""; }
                }
            }
            W.IconButton {
                objectName: "picturesFiltersButton"
                iconName: "sliders-horizontal"
                text: "Filters"
                highlighted: root.filtersOpen
                enabled: !root.favoritesView && root.providerCatalogReady && !!(root.providerDescriptor(root.providerId).filters || []).length
                onClicked: {
                    root.filtersOpen = !root.filtersOpen;
                    root.syncFilterControls();
                }
            }
            W.Choice {
                id: providerChoice
                objectName: "picturesProviderChoice"
                width: 145
                model: root.providerOptions.map(value => value.name)
                currentIndex: 0
                enabled: !root.favoritesView && root.providerCatalogReady
                Accessible.name: "Wallpaper provider"
                onActivated: index => root.selectProvider(root.providerOptions[index].id)
            }
            W.IconButton {
                objectName: "wallpaperViewButton"
                iconName: root.gridMode ? "panels-top-left" : "layout-grid"
                text: root.gridMode ? "Show wallpaper strip" : "Show wallpaper grid"
                highlighted: root.gridMode
                onClicked: {
                    root.gridMode = !root.gridMode;
                    Qt.callLater(root.focusCatalogue);
                }
            }
            W.IconButton {
                objectName: "randomWallpaperButton"
                iconName: "dices"
                text: "Select a random " + root.providerName(root.providerId) + " image"
                visible: root.providerSupports(root.providerId, "random")
                enabled: !root.randomLoading && root.providerCatalogReady
                onClicked: root.chooseRandom()
            }
        }

        RowLayout {
            visible: !!root.error
            Layout.fillWidth: true
            W.Label { text: root.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
            W.Action { text: "Retry"; onClicked: root.browse(false) }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0

            GridView {
                id: grid
                objectName: "wallpaperGrid"
                visible: root.gridMode
                x: 0
                y: 0
                width: parent.width * 0.39
                height: parent.height
                clip: true
                model: catalogue
                cellWidth: width / Math.max(2, Math.floor(width / 170))
                cellHeight: cellWidth * 0.68
                keyNavigationEnabled: true
                keyNavigationWraps: false
                delegate: WallpaperTile {
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    highlighted: root.wallpaperKey(root.selected) === root.wallpaperKey(wallpaper)
                    onClicked: {
                        grid.forceActiveFocus();
                        grid.currentIndex = index;
                        root.selectWallpaper(wallpaper);
                    }
                }
                onCurrentIndexChanged: if (activeFocus && currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
                Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
                Keys.onEnterPressed: if (currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
                onContentYChanged: pagination.restart()
                onContentHeightChanged: pagination.restart()
                onHeightChanged: pagination.restart()
                W.WheelScroll { view: grid; pixelsPerNotch: Math.max(360, grid.cellHeight * 1.25) }
                ScrollBar.vertical: ScrollBar {}
            }

            GridLayout {
                id: selectedLayout
                x: root.gridMode ? parent.width * 0.41 : 0
                y: 0
                width: root.gridMode ? parent.width * 0.59 : parent.width
                height: parent.height
                columns: root.gridMode ? 1 : 2
                columnSpacing: 24
                rowSpacing: 12
                visible: !!root.selected.id

                Rectangle {
                    id: wallpaperPreviewFrame
                    Layout.row: root.gridMode ? 1 : 0
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 180
                    Layout.minimumHeight: root.gridMode ? 180 : 0
                    Layout.preferredWidth: root.gridMode ? selectedLayout.width : selectedLayout.width * 0.53
                    color: Theme.scrim(0.45)
                    radius: 8
                    clip: true
                    W.CrossfadeImage {
                        id: wallpaperPreview
                        objectName: "selectedWallpaperImage"
                        anchors.fill: parent
                        anchors.margins: 6
                        source: root.selectedImageSource
                        fillMode: Image.PreserveAspectFit
                        fadeInOnTop: true
                        imageWidth: Math.min(root.selected.width || 3840, Math.max(400, Math.ceil(root.fittedImageWidth() * 1.5)))
                        onDisplayedSourceChanged: root.upgradeSelectedImage()
                        onWidthChanged: root.upgradeSelectedImage()
                        onHeightChanged: root.upgradeSelectedImage()
                    }
                }

                ColumnLayout {
                    Layout.row: 0
                    Layout.column: root.gridMode ? 0 : 1
                    Layout.fillWidth: true
                    Layout.fillHeight: !root.gridMode
                    Layout.minimumWidth: 220
                    Layout.preferredWidth: root.gridMode ? selectedLayout.width : selectedLayout.width * 0.47
                    Layout.preferredHeight: root.gridMode ? implicitHeight : selectedLayout.height
                    spacing: 12

                    W.Label {
                        Layout.fillWidth: true
                        text: root.selected.title || (root.providerName(root.selected.provider || root.providerId) + " " + (root.selected.id || ""))
                        font.pixelSize: Math.min(36, root.width / 34)
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    W.Label {
                        Layout.fillWidth: true
                        text: [root.selected.resolution, root.selected.fileType ? root.selected.fileType.split("/").pop().toUpperCase() : "", root.selected.fileSize ? root.prettySize(root.selected.fileSize) : ""].filter(Boolean).join("   ·   ")
                        color: Theme.muted
                        wrapMode: Text.Wrap
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: root.selected.metadata || []
                            delegate: W.Label {
                                required property var modelData
                                text: modelData.label + ": " + modelData.value
                                color: Theme.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                    W.Label {
                        visible: !!root.selected.attribution
                        Layout.fillWidth: true
                        text: root.selected.attribution || ""
                        color: Theme.muted
                        wrapMode: Text.Wrap
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: root.selected.colors || []
                            Rectangle {
                                required property string modelData
                                width: 24; height: 16; radius: 3
                                color: modelData
                                border.width: 1
                                border.color: "#66ffffff"
                                visible: root.selected.colors && root.selected.colors.length > 0
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        W.Action {
                            iconName: "image"
                            text: "View full image"
                            enabled: !!root.selected.path
                            onClicked: gallery.show([{url: root.selected.path}], 0, root.selected.title || "Wallpaper")
                        }
                        W.Action {
                            objectName: "setWallpaperButton"
                            iconName: "monitor"
                            text: root.settingWallpaper ? "Setting wallpaper…" : "Set as desktop wallpaper"
                            enabled: !!root.selected.id && !root.settingWallpaper
                            onClicked: root.setDesktopWallpaper()
                        }
                        W.IconButton {
                            objectName: "favoriteWallpaperButton"
                            iconName: root.isFavorite(root.selected) ? "star-filled" : "star"
                            text: root.isFavorite(root.selected) ? "Remove from Favorites" : "Add to Favorites"
                            enabled: !!root.selected.id && !root.favoriteSaving
                            onClicked: root.toggleFavorite()
                        }
                        W.Action {
                            iconName: "globe"
                            text: "Open on " + (root.selected.siteName || root.providerName(root.selected.provider || root.providerId))
                            enabled: !!root.selected.url
                            onClicked: Browser.open(root.selected.url, "pictures")
                        }
                    }
                    BusyIndicator { visible: root.settingWallpaper; running: visible; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                    W.Label {
                        visible: !!root.actionMessage
                        Layout.fillWidth: true
                        text: root.actionMessage
                        color: root.settingWallpaper ? Theme.muted : root.actionFailed ? Theme.danger : Theme.text
                        wrapMode: Text.Wrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            W.Label {
                anchors.centerIn: parent
                visible: !root.selected.id && !root.loading && !root.error
                text: root.favoritesView ? "No saved wallpapers yet." : "No matching wallpapers."
                color: Theme.muted
            }
        }

        ListView {
            id: rail
            objectName: "wallpaperRail"
            visible: !root.gridMode
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(205, root.height * 0.27)
            Layout.minimumHeight: 120
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            model: catalogue
            keyNavigationEnabled: true
            keyNavigationWraps: false
            delegate: WallpaperTile {
                width: Math.max(150, Math.min(270, (rail.height - 38) * 1.72))
                height: rail.height - 12
                highlighted: root.wallpaperKey(root.selected) === root.wallpaperKey(wallpaper)
                onClicked: { rail.forceActiveFocus(); rail.currentIndex = index; root.selectWallpaper(wallpaper); }
            }
            onCurrentIndexChanged: if (activeFocus && currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
            Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
            Keys.onEnterPressed: if (currentIndex >= 0 && currentIndex < root.wallpapers.length) root.selectWallpaper(root.wallpapers[currentIndex])
            onContentXChanged: pagination.restart()
            W.WheelScroll { view: rail; horizontal: true; pixelsPerNotch: 360 }
            ScrollBar.horizontal: ScrollBar {}
        }
    }

    function prettySize(value) {
        let size = Number(value || 0), unit = "B";
        for (const next of ["KB", "MB", "GB"]) {
            if (size < 1024) break;
            size /= 1024; unit = next;
        }
        return (unit === "B" ? Math.round(size) : size.toFixed(1)) + " " + unit;
    }
}
