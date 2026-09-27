import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Io
import "../../core"
import "../../widgets" as W

ColumnLayout {
    id: root
    property var host
    property var results: []
    property var stationRows: []
    property var stationRowsByKey: ({})
    property var favorites: []
    property var countries: []
    property var genres: []
    property var selectedGenres: []
    property string countryName: ""
    property string searchQuery: ""
    property string countryQuery: ""
    property string genreQuery: ""
    property string browseError: ""
    property string favoriteError: ""
    property string countryError: ""
    property string genreError: ""
    property string playStatus: ""
    property string playingStationUuid: ""
    property string playingGroupKey: ""
    property string playingStationName: ""
    property string playingIpcPath: ""
    property string nowPlayingSong: ""
    property var qualitySelections: ({})
    property var playerProcess: null
    property var faviconSources: ({})
    property var faviconPending: ({})
    property bool metadataPending: false
    property bool loading: true
    property bool loadingMore: false
    property bool countriesLoading: false
    property bool countriesLoaded: false
    property bool genresLoading: false
    property bool genresLoaded: false
    property bool favoritesLoaded: false
    property int nextOffset: -1
    property int browseGeneration: 0
    property int playGeneration: 0
    readonly property bool hasBrowseFilters: searchQuery.trim().length > 0 || !!countryName || selectedGenres.length > 0
    readonly property string playbackStatusText: nowPlayingSong && playingStationName ? nowPlayingSong + " · " + playingStationName : playStatus
    readonly property var countryOptions: [{name: "All countries", stationcount: 0, all: true}].concat(countries)
    readonly property var visibleCountries: countryOptions.filter(item => item.name.toLowerCase().includes(countryQuery.trim().toLowerCase()))
    readonly property var visibleGenres: genres.filter(item => item.name.toLowerCase().includes(genreQuery.trim().toLowerCase()))
    spacing: 10
    RadioService {
        id: service
        onFailed: message => root.browseError = message
    }
    ListModel { id: stationRowsModel }

    function activate() {
        stationList.forceActiveFocus();
        if (stationRows.length && stationList.currentIndex < 0) stationList.currentIndex = 0;
    }

    function isFavorite(stationUuid) {
        return favorites.some(station => station.groupKey === stationUuid);
    }

    function siteKey(url) {
        return String(url || "").trim().toLowerCase().replace(/^https?:\/\//, "").split(/[/?#]/)[0].replace(/^www\./, "");
    }

    function stationGroupKey(station) {
        const name = String(station.name || "").toLowerCase().replace(/[’‘]/g, "'").replace(/['`\"]/g, "").replace(/&/g, " and ").replace(/[.,;:!?(){}\[\]\/\\_-]+/g, " ").replace(/\s+/g, " ").trim();
        const country = String(station.countrycode || station.country || "").toLowerCase();
        const source = siteKey(station.homepage) || siteKey(station.favicon) || siteKey(station.url_resolved) || siteKey(station.url);
        return country + "|" + name + "|" + source;
    }

    function buildQualityOptions(variants) {
        const choices = [];
        const seen = new Set();
        for (const variant of variants) {
            const codec = String(variant.codec || "").trim().toUpperCase();
            const bitrate = Number(variant.bitrate) || 0;
            const key = codec + "|" + bitrate;
            if (bitrate || codec) {
                if (seen.has(key)) continue;
                seen.add(key);
            }
            const fallbackLabel = "Stream " + (choices.length + 1);
            choices.push({
                stationuuid: variant.stationuuid,
                codec: codec,
                bitrate: bitrate,
                label: [codec, bitrate ? bitrate + " kbps" : ""].filter(Boolean).join(" · ") || fallbackLabel
            });
        }
        return choices;
    }

    function groupStations(items) {
        const grouped = new Map();
        for (const station of items || []) {
            if (!station || !station.stationuuid || !station.name) continue;
            const key = stationGroupKey(station);
            if (!grouped.has(key)) grouped.set(key, {variants: [], seen: new Set()});
            const group = grouped.get(key);
            if (group.seen.has(station.stationuuid)) continue;
            group.seen.add(station.stationuuid);
            group.variants.push(station);
        }
        return Array.from(grouped, ([groupKey, group]) => {
            const variants = group.variants.slice().sort((a, b) => (Number(b.bitrate) || 0) - (Number(a.bitrate) || 0) || (Number(b.clickcount) || 0) - (Number(a.clickcount) || 0));
            const best = variants[0];
            const tags = Array.from(new Set(variants.reduce((all, variant) => all.concat(String(variant.tags || "").split(",").map(tag => tag.trim()).filter(Boolean)), [])));
            const logoVariant = variants.find(variant => /^https?:\/\//i.test(variant.favicon || ""));
            const qualityOptions = buildQualityOptions(variants);
            return Object.assign({}, best, {
                groupKey: groupKey,
                variants: variants,
                favicon: logoVariant ? logoVariant.favicon : "",
                tags: tags.join(", "),
                qualityOptions: qualityOptions,
                qualityLabel: qualityOptions.length ? qualityOptions[0].label : ""
            });
        });
    }

    function selectQuality(station, index) {
        const choices = station.qualityOptions || [];
        if (index < 0 || index >= choices.length) return;
        const next = Object.assign({}, qualitySelections);
        next[station.groupKey] = choices[index].stationuuid;
        qualitySelections = next;
        if (playingGroupKey === station.groupKey) playStation(-1, station);
    }

    function pollNowPlaying() {
        const ipcPath = playingIpcPath;
        const generation = playGeneration;
        if (metadataPending || !ipcPath || !playerProcess || !playStatus.startsWith("Playing ")) return;
        metadataPending = true;
        service.request("metadata", {ipcPath: ipcPath}, (result, failure) => {
            root.metadataPending = false;
            if (generation !== root.playGeneration || ipcPath !== root.playingIpcPath || failure) return;
            const title = String(result && result.title || "").replace(/\s+/g, " ").trim();
            const normalizedTitle = title.toLowerCase();
            const normalizedStation = root.playingStationName.trim().toLowerCase();
            root.nowPlayingSong = !title || normalizedTitle === normalizedStation || /^https?:\/\//i.test(title) ? "" : title;
        });
    }

    function loadFavicon(url) {
        if (!/^https?:\/\//i.test(url || "") || Object.prototype.hasOwnProperty.call(faviconSources, url) || faviconPending[url]) return;
        const pending = Object.assign({}, faviconPending);
        pending[url] = true;
        faviconPending = pending;
        service.request("favicon", {url: url}, (result, failure) => {
            const nextPending = Object.assign({}, root.faviconPending);
            delete nextPending[url];
            root.faviconPending = nextPending;
            const nextSources = Object.assign({}, root.faviconSources);
            nextSources[url] = !failure && result && result.source ? result.source : "";
            root.faviconSources = nextSources;
        });
    }

    function rowsForDisplay() {
        let rows = groupStations(results);
        if (!hasBrowseFilters) {
            const seen = new Set(favorites.map(station => station.groupKey));
            rows = favorites.concat(rows.filter(station => !seen.has(station.groupKey)));
        }
        return rows;
    }

    function indexRowsByKey(rows) {
        const indexed = {};
        for (const row of rows) indexed[row.groupKey] = row;
        stationRowsByKey = indexed;
    }

    function rebuildStationModel(rows) {
        stationRowsModel.clear();
        for (const row of rows) stationRowsModel.append({groupKey: row.groupKey});
    }

    function appendStationRows() {
        const rows = rowsForDisplay();
        const oldCount = stationRowsModel.count;
        let existingRowsArePrefix = oldCount <= rows.length;
        for (let i = 0; existingRowsArePrefix && i < oldCount; ++i)
            existingRowsArePrefix = stationRowsModel.get(i).groupKey === rows[i].groupKey;

        stationRows = rows;
        indexRowsByKey(rows);
        if (!existingRowsArePrefix) {
            rebuildStationModel(rows);
            return;
        }
        for (let i = oldCount; i < rows.length; ++i)
            stationRowsModel.append({groupKey: rows[i].groupKey});
    }

    function refreshRows(preserveSelection) {
        const previousContentY = preserveSelection
            ? stationList.contentY
            : 0;
        const selectedUuid = preserveSelection && stationList.currentIndex >= 0 && stationList.currentIndex < stationRows.length
            ? stationRows[stationList.currentIndex].groupKey : "";
        const rows = rowsForDisplay();
        stationRows = rows;
        indexRowsByKey(rows);
        rebuildStationModel(rows);
        if (selectedUuid) {
            const index = rows.findIndex(station => station.groupKey === selectedUuid);
            stationList.currentIndex = index >= 0 ? index : (rows.length ? 0 : -1);
        } else {
            stationList.currentIndex = rows.length ? 0 : -1;
        }
        if (preserveSelection) {
            Qt.callLater(() => {
                const maxContentY = Math.max(0, stationList.contentHeight - stationList.height);
                stationList.contentY = Math.max(0, Math.min(previousContentY, maxContentY));
            });
        }
    }

    function saveFavorites() {
        service.request("favorites-save", {favorites: favorites}, (result, failure) => {
            favoriteError = failure || "";
        });
    }

    function toggleFavorite(station) {
        if (isFavorite(station.groupKey)) {
            favorites = favorites.filter(item => item.groupKey !== station.groupKey);
        } else {
            favorites = [station].concat(favorites);
        }
        saveFavorites();
        refreshRows(true);
    }

    function browse(append) {
        if (append && (loading || nextOffset < 0)) return;
        const generation = ++browseGeneration;
        const offset = append ? nextOffset : 0;
        if (!append) {
            results = [];
            nextOffset = -1;
            browseError = "";
            refreshRows(false);
        }
        loading = true;
        loadingMore = append;
        service.request("browse", {
            query: searchQuery.trim(),
            country: countryName,
            tags: selectedGenres,
            offset: offset
        }, (result, failure) => {
            if (generation !== browseGeneration) return;
            loading = false;
            loadingMore = false;
            if (failure) {
                browseError = failure;
                if (!append) {
                    results = [];
                    refreshRows(false);
                }
                return;
            }
            const incoming = result && Array.isArray(result.items) ? result.items : [];
            if (append) {
                const seen = new Set(results.map(station => station.stationuuid));
                results = results.concat(incoming.filter(station => !seen.has(station.stationuuid)));
            } else {
                results = incoming;
            }
            nextOffset = result && result.nextOffset >= 0 ? result.nextOffset : -1;
            browseError = "";
            if (append) appendStationRows();
            else refreshRows(false);
        });
    }

    function scheduleBrowse() { browseDelay.restart(); }

    function loadCountries() {
        if (countriesLoaded || countriesLoading) return;
        countriesLoading = true;
        countryError = "";
        service.request("countries", {}, (result, failure) => {
            countriesLoading = false;
            if (failure) { countryError = failure; return; }
            countries = Array.isArray(result) ? result : [];
            countriesLoaded = true;
            countryError = "";
        });
    }

    function loadGenres() {
        if (genresLoaded || genresLoading) return;
        genresLoading = true;
        genreError = "";
        service.request("genres", {}, (result, failure) => {
            genresLoading = false;
            if (failure) { genreError = failure; return; }
            genres = Array.isArray(result) ? result : [];
            genresLoaded = true;
            genreError = "";
        });
    }

    function selectCountry(option) {
        countryName = option.all ? "" : option.name;
        countryPopup.close();
        scheduleBrowse();
        countryButton.forceActiveFocus();
    }

    function toggleGenre(name) {
        const index = selectedGenres.indexOf(name);
        selectedGenres = index >= 0 ? selectedGenres.filter(tag => tag !== name) : selectedGenres.concat([name]);
        scheduleBrowse();
    }

    function toggleGenreFromList(index) {
        if (index < 0 || index >= visibleGenres.length) return;
        toggleGenre(visibleGenres[index].name);
    }

    function loadFavorites() {
        service.request("favorites-load", {}, (saved, failure) => {
            favoriteError = failure || "";
            const records = [];
            if (Array.isArray(saved)) {
                for (const favorite of saved) {
                    const variants = favorite && Array.isArray(favorite.variants) && favorite.variants.length ? favorite.variants : (favorite ? [favorite] : []);
                    records.push(...variants);
                }
            }
            favorites = groupStations(records);
            favoritesLoaded = true;
            refreshRows(true);
        });
    }

    function popupBelow(button, popup) {
        const point = button.mapToItem(root, 0, button.height);
        popup.x = Math.max(0, Math.min(point.x, root.width - popup.width));
        popup.y = Math.max(0, Math.min(point.y + 5, root.height - popup.height));
    }

    function showCountryPopup() {
        popupBelow(countryButton, countryPopup);
        countryPopup.open();
    }

    function showGenrePopup() {
        popupBelow(genreButton, genrePopup);
        genrePopup.open();
    }

    function playStation(index, stationOverride) {
        const station = stationOverride || (index >= 0 && index < stationRows.length ? stationRows[index] : null);
        if (!station) return;
        const variants = station.variants || [station];
        const selectedUuid = qualitySelections[station.groupKey] || "";
        let stream = variants.find(variant => variant.stationuuid === selectedUuid) || variants[0] || station;
        if (stream.stationuuid === playingStationUuid && playerProcess) return;
        const generation = ++playGeneration;
        playStatus = "Connecting to " + station.name + "…";
        nowPlayingSong = "";
        service.request("play", {stationuuid: stream.stationuuid}, (result, failure) => {
            if (generation !== playGeneration) return;
            if (failure || !result || !Array.isArray(result.command)) {
                playStatus = failure || "Could not resolve this station stream.";
                return;
            }
            const previous = playerProcess;
            const previousIpcPath = playingIpcPath;
            playerProcess = null;
            if (previous) previous.destroy();
            if (previousIpcPath) service.request("metadata-cleanup", {ipcPath: previousIpcPath}, () => {});
            const next = streamPlayerComponent.createObject(root, {playerCommand: result.command});
            if (!next) {
                playStatus = "Could not start the audio player.";
                return;
            }
            playerProcess = next;
            playingStationUuid = stream.stationuuid;
            playingGroupKey = station.groupKey;
            playingStationName = station.name;
            playingIpcPath = result.ipcPath || "";
            nowPlayingSong = "";
            playStatus = "Playing " + station.name;
        });
    }

    function stopPlayback() {
        ++playGeneration;
        const previous = playerProcess;
        const ipcPath = playingIpcPath;
        playerProcess = null;
        playingIpcPath = "";
        playingStationUuid = "";
        playingGroupKey = "";
        playingStationName = "";
        nowPlayingSong = "";
        playStatus = "Playback stopped.";
        if (previous) previous.destroy();
        if (ipcPath) service.request("metadata-cleanup", {ipcPath: ipcPath}, () => {});
    }

    function playerExited(process, code) {
        if (playerProcess !== process) return;
        playerProcess = null;
        process.destroy();
        const ipcPath = playingIpcPath;
        playingIpcPath = "";
        if (ipcPath) service.request("metadata-cleanup", {ipcPath: ipcPath}, () => {});
        if (code !== 0) playStatus = "The stream ended or could not be played.";
        else playStatus = "Playback ended.";
        playingStationUuid = "";
        playingGroupKey = "";
        playingStationName = "";
        nowPlayingSong = "";
    }

    function maybeLoadMore() {
        if (nextOffset < 0 || loading || stationList.contentHeight <= stationList.height) return;
        if (stationList.contentY + stationList.height >= stationList.contentHeight - Math.max(180, stationList.height * 0.35))
            browse(true);
    }

    Component {
        id: streamPlayerComponent
        Process {
            id: streamProcess
            property var playerCommand: []
            command: playerCommand
            running: true
            onExited: (code, status) => root.playerExited(streamProcess, code)
        }
    }

    Component.onCompleted: {
        loadFavorites();
        refreshRows(false);
        browse(false);
    }

    Component.onDestruction: {
        const previous = playerProcess;
        const ipcPath = playingIpcPath;
        playerProcess = null;
        if (previous) previous.destroy();
        if (ipcPath) service.request("metadata-cleanup", {ipcPath: ipcPath}, () => {});
    }

    Timer {
        id: browseDelay
        interval: 350
        onTriggered: root.browse(false)
    }

    Timer {
        id: paginationDelay
        interval: 140
        onTriggered: root.maybeLoadMore()
    }

    Timer {
        id: nowPlayingTimer
        interval: 2500
        repeat: true
        running: !!root.playerProcess && !!root.playingIpcPath
        onTriggered: root.pollNowPlaying()
    }

    Component {
        id: countryPopupDelegate
        ItemDelegate {
            id: countryOption
            required property var modelData
            required property int index
            width: countryList.width
            height: 38
            highlighted: countryList.currentIndex === index
            contentItem: RowLayout {
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: countryOption.highlighted ? Theme.accent : Theme.text
                    elide: Text.ElideRight
                }
            }
            background: Rectangle {
                color: countryOption.highlighted ? Theme.raised : countryOption.hovered ? Theme.surface : "transparent"
                radius: Theme.controlRadius
            }
            onClicked: root.selectCountry(modelData)
        }
    }

    RowLayout {
        id: toolbar
        Layout.fillWidth: true
        spacing: 8

        W.SearchField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search radio stations…"
            onTextChanged: { root.searchQuery = text; root.scheduleBrowse(); }
            onAccepted: {
                browseDelay.stop();
                root.browse(false);
                root.activate();
            }
            Keys.onDownPressed: (event) => {
                root.activate();
                event.accepted = true;
            }
        }

        Button {
            id: countryButton
            Layout.preferredWidth: 205
            Layout.minimumWidth: 150
            Layout.preferredHeight: 42
            hoverEnabled: true
            text: root.countryName || "All countries"
            Accessible.name: "Country filter: " + text
            contentItem: RowLayout {
                spacing: 8
                Label { Layout.fillWidth: true; text: countryButton.text; color: Theme.text; elide: Text.ElideRight }
                W.Icon { name: "chevron-down"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
            }
            background: Rectangle {
                color: countryButton.down ? Theme.raised : countryButton.hovered ? Theme.raised : Theme.surface
                border.color: countryButton.activeFocus ? Theme.accent : Theme.border
                radius: Theme.controlRadius
            }
            onClicked: root.showCountryPopup()
        }

        Button {
            id: genreButton
            Layout.preferredWidth: 170
            Layout.minimumWidth: 130
            Layout.preferredHeight: 42
            hoverEnabled: true
            text: root.selectedGenres.length ? "Genres (" + root.selectedGenres.length + ")" : "All genres"
            Accessible.name: "Genre filter: " + text
            contentItem: RowLayout {
                spacing: 8
                Label { Layout.fillWidth: true; text: genreButton.text; color: Theme.text; elide: Text.ElideRight }
                W.Icon { name: "chevron-down"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
            }
            background: Rectangle {
                color: genreButton.down ? Theme.raised : genreButton.hovered ? Theme.raised : Theme.surface
                border.color: genreButton.activeFocus ? Theme.accent : Theme.border
                radius: Theme.controlRadius
            }
            onClicked: root.showGenrePopup()
        }
    }

    Popup {
        id: countryPopup
        parent: root
        popupType: Popup.Item
        width: Math.max(260, countryButton.width)
        height: Math.min(400, root.height - 16)
        padding: 6
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
        onOpened: {
            root.loadCountries();
            countrySearch.text = "";
            countryList.currentIndex = Math.max(0, root.visibleCountries.findIndex(option => option.all ? !root.countryName : option.name === root.countryName));
            countryList.positionViewAtIndex(countryList.currentIndex, ListView.Contain);
            countrySearch.forceActiveFocus();
        }
        onClosed: countryButton.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: 6
            W.SearchField {
                id: countrySearch
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                placeholderText: "Search countries…"
                onTextChanged: {
                    root.countryQuery = text;
                    countryList.currentIndex = root.visibleCountries.length ? 0 : -1;
                }
                Keys.onDownPressed: (event) => {
                    countryList.currentIndex = Math.max(0, countryList.currentIndex);
                    countryList.forceActiveFocus();
                    event.accepted = true;
                }
            }
            Label {
                visible: root.countriesLoading
                text: "Loading countries…"
                color: Theme.muted
                Layout.fillWidth: true
                leftPadding: 6
            }
            Label {
                visible: !!root.countryError
                text: root.countryError
                color: Theme.danger
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                leftPadding: 6
            }
            ListView {
                id: countryList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.countriesLoaded || root.visibleCountries.length > 0
                clip: true
                model: root.visibleCountries
                delegate: countryPopupDelegate
                keyNavigationEnabled: true
                currentIndex: 0
                onModelChanged: currentIndex = root.visibleCountries.length ? 0 : -1
                W.WheelScroll { view: countryList; pixelsPerNotch: 440; pixelMultiplier: 1.9 }
                ScrollBar.vertical: ScrollBar {}
                Keys.onReturnPressed: (event) => { if (currentIndex >= 0) root.selectCountry(root.visibleCountries[currentIndex]); event.accepted = true; }
                Keys.onEnterPressed: (event) => { if (currentIndex >= 0) root.selectCountry(root.visibleCountries[currentIndex]); event.accepted = true; }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.countriesLoaded && !root.visibleCountries.length
                Label {
                    anchors.centerIn: parent
                    text: "No matching countries."
                    color: Theme.muted
                }
            }
        }
    }

    Popup {
        id: genrePopup
        parent: root
        popupType: Popup.Item
        width: 340
        height: Math.min(460, root.height - 16)
        padding: 8
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
        onOpened: {
            root.loadGenres();
            genreSearch.text = "";
            root.genreQuery = "";
            genreList.currentIndex = 0;
            genreSearch.forceActiveFocus();
        }
        onClosed: genreButton.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: "Genres"
                    color: Theme.text
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Button {
                    visible: root.selectedGenres.length > 0
                    text: "Clear"
                    implicitWidth: 54
                    implicitHeight: 28
                    hoverEnabled: true
                    contentItem: Label {
                        text: parent.text
                        color: parent.hovered ? Theme.accent : Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                    }
                    background: Rectangle {
                        radius: Theme.controlRadius
                        color: parent.hovered ? Theme.raised : "transparent"
                    }
                    onClicked: {
                        root.selectedGenres = [];
                        root.scheduleBrowse();
                    }
                }
            }
            W.SearchField {
                id: genreSearch
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                placeholderText: "Search genres…"
                onTextChanged: { root.genreQuery = text; genreList.currentIndex = root.visibleGenres.length ? 0 : -1; }
                Keys.onDownPressed: (event) => {
                    genreList.currentIndex = Math.max(0, genreList.currentIndex);
                    genreList.forceActiveFocus();
                    event.accepted = true;
                }
            }
            Label {
                visible: root.genresLoading
                text: "Loading genres…"
                color: Theme.muted
                Layout.fillWidth: true
            }
            Label {
                visible: !!root.genreError
                text: root.genreError
                color: Theme.danger
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            ListView {
                id: genreList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.genresLoaded || root.visibleGenres.length > 0
                clip: true
                model: root.visibleGenres
                keyNavigationEnabled: true
                currentIndex: root.visibleGenres.length ? 0 : -1
                onModelChanged: currentIndex = root.visibleGenres.length ? 0 : -1
                W.WheelScroll { view: genreList; pixelsPerNotch: 440; pixelMultiplier: 1.9 }
                ScrollBar.vertical: ScrollBar {}
                delegate: CheckBox {
                    id: genreOption
                    required property var modelData
                    required property int index
                    width: genreList.width
                    height: 34
                    text: modelData.name
                    checked: root.selectedGenres.includes(modelData.name)
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    leftPadding: 0
                    rightPadding: 0
                    contentItem: Label {
                        text: genreOption.text
                        color: genreOption.activeFocus || (genreList.activeFocus && genreList.currentIndex === genreOption.index) ? Theme.accent : Theme.text
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 30
                        elide: Text.ElideRight
                    }
                    indicator: Rectangle {
                        implicitWidth: 18
                        implicitHeight: 18
                        x: 4
                        y: (genreOption.height - height) / 2
                        radius: 3
                        color: genreOption.checked ? Theme.accent : Theme.background
                        border.color: genreOption.checked ? Theme.accent : Theme.border
                        W.Icon {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            name: "check"
                            visible: genreOption.checked
                        }
                    }
                    background: Rectangle {
                        color: genreOption.hovered || genreOption.activeFocus || (genreList.activeFocus && genreList.currentIndex === genreOption.index) ? Theme.raised : "transparent"
                        radius: Theme.controlRadius
                    }
                    onToggled: root.toggleGenre(modelData.name)
                    Keys.onDownPressed: (event) => {
                        genreList.currentIndex = Math.min(genreList.count - 1, index + 1);
                        genreList.positionViewAtIndex(genreList.currentIndex, ListView.Contain);
                        Qt.callLater(() => { if (genreList.currentItem) genreList.currentItem.forceActiveFocus(); });
                        event.accepted = true;
                    }
                    Keys.onUpPressed: (event) => {
                        if (index === 0) genreSearch.forceActiveFocus();
                        else {
                            genreList.currentIndex = index - 1;
                            genreList.positionViewAtIndex(genreList.currentIndex, ListView.Contain);
                            Qt.callLater(() => { if (genreList.currentItem) genreList.currentItem.forceActiveFocus(); });
                        }
                        event.accepted = true;
                    }
                }
                Keys.onSpacePressed: (event) => { root.toggleGenreFromList(currentIndex); event.accepted = true; }
                Keys.onReturnPressed: (event) => { root.toggleGenreFromList(currentIndex); event.accepted = true; }
                Keys.onEnterPressed: (event) => { root.toggleGenreFromList(currentIndex); event.accepted = true; }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.genresLoaded && !root.visibleGenres.length
                Label {
                    anchors.centerIn: parent
                    text: root.genreQuery.trim() ? "No matching genres." : "No genres available."
                    color: Theme.muted
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 10
        Label {
            Layout.fillWidth: true
            text: root.playbackStatusText
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            color: root.nowPlayingSong || root.playStatus.startsWith("Playing ") ? Theme.accent : root.playStatus.startsWith("The stream") ? Theme.danger : Theme.muted
            elide: Text.ElideRight
        }
        W.IconButton {
            opacity: root.nowPlayingSong ? 1 : 0
            enabled: !!root.nowPlayingSong
            iconName: "copy"
            iconSize: 18
            width: 32
            height: 32
            implicitWidth: 32
            implicitHeight: 32
            text: "Copy current song title"
            onClicked: Quickshell.clipboardText = root.nowPlayingSong
        }
        W.IconButton {
            opacity: root.playerProcess ? 1 : 0
            enabled: !!root.playerProcess
            iconName: "square"
            iconSize: 18
            width: 32
            height: 32
            implicitWidth: 32
            implicitHeight: 32
            text: "Stop radio playback"
            onClicked: root.stopPlayback()
        }
    }

    ListView {
        id: stationList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: stationRowsModel
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: false
        onContentYChanged: paginationDelay.restart()
        onCurrentIndexChanged: {
            if (currentIndex >= 0 && currentIndex < root.stationRows.length)
                positionViewAtIndex(currentIndex, ListView.Contain);
        }
        W.WheelScroll { view: stationList }
        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: stationRow
            required property string groupKey
            required property int index
            readonly property var station: root.stationRowsByKey[groupKey] || ({})
            readonly property bool selected: stationList.currentIndex === index && stationList.activeFocus
            readonly property bool isPlaying: root.playingGroupKey === station.groupKey
            readonly property string flagUrl: /^[A-Z]{2}$/.test(station.countrycode || "")
                ? "https://flagcdn.com/w40/" + station.countrycode.toLowerCase() + ".png" : ""
            width: ListView.view.width
            height: 52

            Rectangle {
                anchors.fill: parent
                radius: Theme.controlRadius
                color: stationRowMouse.containsMouse ? Theme.surface : stationRow.selected ? Theme.accentSurface : "transparent"
                border.color: stationRow.selected ? Theme.accent : "transparent"
                border.width: stationRow.selected ? 1 : 0
            }

            MouseArea {
                id: stationRowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    stationList.currentIndex = stationRow.index;
                    stationList.forceActiveFocus();
                }
                onDoubleClicked: {
                    stationList.currentIndex = stationRow.index;
                    stationList.forceActiveFocus();
                    root.playStation(stationRow.index);
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 16
                    radius: 2
                    color: Theme.raised
                    clip: true
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: root.faviconSources[stationRow.flagUrl] || ""
                        Component.onCompleted: root.loadFavicon(stationRow.flagUrl)
                    }
                }
                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Image {
                        anchors.fill: parent
                        source: root.faviconSources[stationRow.station.favicon] || ""
                        sourceSize.width: 60
                        sourceSize.height: 60
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        Component.onCompleted: root.loadFavicon(stationRow.station.favicon)
                    }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    text: stationRow.station.name
                    color: stationRow.isPlaying ? Theme.accent : Theme.text
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                Label {
                    Layout.preferredWidth: Math.min(270, Math.max(100, stationList.width * 0.26))
                    text: (stationRow.station.tags || "").split(",").map(tag => tag.trim()).filter(tag => !!tag).slice(0, 4).join(", ")
                    color: Theme.muted
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                ComboBox {
                    id: qualitySelector
                    visible: stationRow.station.qualityOptions.length > 1
                    Layout.preferredWidth: Math.min(180, Math.max(140, stationList.width * 0.15))
                    Layout.minimumWidth: 120
                    Layout.maximumWidth: 180
                    Layout.preferredHeight: 32
                    model: stationRow.station.qualityOptions
                    textRole: "label"
                    valueRole: "stationuuid"
                    currentIndex: {
                        const selectedUuid = root.qualitySelections[stationRow.station.groupKey] || "";
                        const choices = stationRow.station.qualityOptions;
                        const selectedIndex = choices.findIndex(choice => choice.stationuuid === selectedUuid);
                        return selectedIndex >= 0 ? selectedIndex : 0;
                    }
                    hoverEnabled: true
                    padding: 0
                    leftPadding: 2
                    rightPadding: 20
                    contentItem: Label {
                        text: qualitySelector.displayText
                        color: qualitySelector.hovered || qualitySelector.activeFocus ? Theme.text : Theme.muted
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 0
                        elide: Text.ElideRight
                    }
                    indicator: W.Icon {
                        name: "chevron-down"
                        width: 12
                        height: 12
                        x: qualitySelector.width - width - 3
                        y: (qualitySelector.height - height) / 2
                        opacity: qualitySelector.hovered || qualitySelector.activeFocus ? 1 : 0.7
                    }
                    background: Item {}
                    delegate: ItemDelegate {
                        required property int index
                        width: qualitySelector.width
                        height: 34
                        text: qualitySelector.textAt(index)
                        highlighted: qualitySelector.highlightedIndex === index
                        hoverEnabled: true
                        contentItem: Label {
                            text: parent.text
                            color: parent.highlighted ? Theme.accent : Theme.text
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            color: parent.highlighted || parent.hovered ? Theme.raised : "transparent"
                            radius: Theme.controlRadius
                        }
                    }
                    popup: Popup {
                        y: qualitySelector.height
                        width: qualitySelector.width
                        implicitHeight: Math.min(contentItem.implicitHeight + padding * 2, 240)
                        padding: 4
                        contentItem: ListView {
                            id: qualityOptionsList
                            clip: true
                            implicitHeight: contentHeight
                            model: qualitySelector.popup.visible ? qualitySelector.delegateModel : null
                            currentIndex: qualitySelector.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator {}
                        }
                        background: Rectangle {
                            color: Theme.surface
                            border.color: Theme.border
                            radius: Theme.controlRadius
                        }
                    }
                    onActivated: index => root.selectQuality(stationRow.station, index)
                }
                Label {
                    visible: stationRow.station.qualityOptions.length <= 1
                    Layout.preferredWidth: Math.min(180, Math.max(140, stationList.width * 0.15))
                    Layout.minimumWidth: 120
                    Layout.maximumWidth: 180
                    text: stationRow.station.qualityLabel || ""
                    color: Theme.muted
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 20
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                W.IconButton {
                    id: favoriteButton
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    width: 32
                    height: 32
                    implicitWidth: 32
                    implicitHeight: 32
                    iconName: root.isFavorite(stationRow.station.groupKey) ? "star-filled" : "star"
                    iconSize: 18
                    opacity: root.isFavorite(stationRow.station.groupKey) || stationRowMouse.containsMouse || hovered || activeFocus || stationRow.selected ? 1 : 0
                    text: (root.isFavorite(stationRow.station.groupKey) ? "Remove " : "Add ") + stationRow.station.name + (root.isFavorite(stationRow.station.groupKey) ? " from favorites" : " to favorites")
                    onClicked: root.toggleFavorite(stationRow.station)
                }
            }
        }

        Keys.onRightPressed: (event) => { root.playStation(currentIndex); event.accepted = true; }
        Keys.onReturnPressed: (event) => { root.playStation(currentIndex); event.accepted = true; }
        Keys.onEnterPressed: (event) => { root.playStation(currentIndex); event.accepted = true; }
        Keys.onSpacePressed: (event) => { root.playStation(currentIndex); event.accepted = true; }

        Label {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - 40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.muted
            visible: !root.stationRows.length && root.favoritesLoaded && !root.loading && !root.countriesLoading && !root.genresLoading && !root.browseError
            text: "No stations match this search and filter set."
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(20, implicitHeight)
        text: {
            const messages = [];
            if (root.browseError) messages.push(root.browseError);
            if (root.favoriteError) messages.push("Could not load or save favorites: " + root.favoriteError);
            if (root.loading || root.loadingMore) messages.push("Loading stations…");
            return messages.join(" · ");
        }
        color: root.browseError || root.favoriteError ? Theme.danger : Theme.muted
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: !!text
    }
}
