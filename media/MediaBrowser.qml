import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import "Countries.js" as Countries
import "../core"
import "../widgets" as W

Item {
    id: root
    property var host
    property string kind: "movie"
    property url backgroundImage: ""
    property var titles: []
    property bool updatingCatalogue: false
    ListModel { id: catalogue }
    ListModel { id: episodeCatalogue }
    // Keep delegates and loaded textures alive: mutate rows instead of resetting a JS-array model.
    function updateCatalogue(items, append) {
        updatingCatalogue = true;
        const existing = new Set(append ? titles.map(t => t.id) : []);
        const additions = items.filter(t => { if (existing.has(t.id)) return false; existing.add(t.id); return true; });
        const next = append ? titles.concat(additions) : additions;
        if (append) {
            for (const title of additions) catalogue.append({key:title.id, payload:JSON.stringify(title)});
        } else {
            const wanted = new Set(next.map(t => t.id));
            for (let i=catalogue.count-1; i>=0; --i) if (!wanted.has(catalogue.get(i).key)) catalogue.remove(i);
            for (let i=0; i<next.length; ++i) {
                const title=next[i], payload=JSON.stringify(title);
                if (i >= catalogue.count || catalogue.get(i).key !== title.id) {
                    let from=i+1;
                    while (from<catalogue.count && catalogue.get(from).key !== title.id) ++from;
                    if (from<catalogue.count) catalogue.move(from,i,1);
                    else catalogue.insert(i,{key:title.id,payload:payload});
                }
                if (catalogue.get(i).payload !== payload) catalogue.setProperty(i,"payload",payload);
            }
        }
        titles = next;
        updatingCatalogue = false;
    }
    property var selected: ({})
    property var personal: ({favorite:false, note:"", url:""})
    property var providers: []
    property var episodeProviders: []
    property var filters: ({})
    property var seasons: []
    property var episodes: []
    property string episodeNext: ""
    property string nextPage: ""
    property string error: ""
    property string detailError: ""
    property bool loading: true
    property bool detailLoading: false
    property bool artworkLoading: false
    property bool seasonsLoading: false
    readonly property bool titleLoading: detailLoading || artworkLoading || seasonsLoading || logo.loading
    property bool episodeLoading: false
    property bool favorites: false
    property bool searchOpen: false
    property bool filtersOpen: false
    property int browseGeneration: 0
    property int selectionGeneration: 0
    property int episodeGeneration: 0
    property string tab: "overview"
    property var links: []
    property string spoiler: ""
    property var personDetails: ({})
    property string personRole: "All"
    property int personGeneration: 0
    readonly property var personCredits: (personDetails.credits || []).filter(t => t.kind === kind)
    readonly property var personRoles: ["All"].concat(Array.from(new Set(personCredits.reduce((roles,t) => roles.concat(t.roles || []),[]))).sort())
    property bool extraLoading: false
    property bool gridMode: false
    property int providerIndex: 0
    property int trailerIndex: 0
    property bool artworkReady: false
    readonly property var trailers: selected.trailers || []
    readonly property var cast: selected.cast || []
    readonly property var directors: uniquePeople(cast.filter(p => ["director","co-director","creator","series director"].includes((p.job || p.role || "").toLowerCase())))
    readonly property var writers: uniquePeople(cast.filter(p => ["writer","screenplay","story","teleplay","novel","characters","original story","comic book"].includes((p.job || p.role || "").toLowerCase())))
    readonly property var stars: cast.filter(p => p.department === "Acting" || (!p.department && !/director|writer|screenplay|creator/i.test(p.role || ""))).slice(0,6)
    Settings {
        id: preferences
        location: "file://" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/zephyrus-shell/media-ui.ini"
    }
    MediaService { id: service; onFailed: message => root.error = message }
    Rectangle {
        x: -28; y: -80; width: root.width + 56; height: root.height + 108
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#ec101115" }
            GradientStop { position: 0.6; color: root.gridMode ? "#dc101115" : "#99101115" }
            GradientStop { position: 1; color: root.gridMode ? "#ec101115" : "#33101115" }
        }
        opacity: root.backgroundImage.toString() ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }
    function sameTitle(a, b) {
        return !!(a.id && b.id && (a.id === b.id ||
            (a.imdbId && a.imdbId === b.imdbId) ||
            (a.tmdbId && a.kind === b.kind && a.tmdbId === b.tmdbId)));
    }
    function uniquePeople(people) {
        const seen = new Set();
        return people.filter(person => { const key = person.id || person.name; if (seen.has(key)) return false; seen.add(key); return true; });
    }
    function activate() { (gridMode ? grid : rail).forceActiveFocus(); }
    onGridModeChanged: { activate(); pagination.restart(); }
    function maybeLoadMore() {
        if (loading || error || !nextPage || favorites) return;
        const nearEnd = gridMode ? grid.contentY + grid.height >= grid.contentHeight - grid.cellHeight * 2
                                 : (rail.contentX > rail.originX || rail.currentIndex >= titles.length - 5) && rail.contentX + rail.width >= rail.contentWidth - rail.width * 0.5;
        if ((gridMode && titles.length < 60) || nearEnd) browse(true);
    }
    function browse(append) {
        if (append && (loading || !nextPage)) return;
        const requestedPage = append ? nextPage : "";
        const generation = ++browseGeneration;
        loading = true; error = "";
        if (!append) service.request("snapshot", {kind:kind,query:search.text,filters:filters,favorites:favorites}, (result, failure) => {
            if (generation !== browseGeneration || !loading || failure || !result) return;
            updateCatalogue(result.items, false);
            nextPage = result.next || "";
            if (titles.length && !titles.some(t => sameTitle(t, selected))) selectTitle(titles[0]);
        });
        service.request("browse", {kind:kind,query:search.text,filters:filters,favorites:favorites,page:append ? nextPage : ""}, (result, failure) => {
            if (generation !== browseGeneration) return;
            loading = false;
            if (failure) { error = failure; return; }
            updateCatalogue(result.items, append);
            nextPage = result.next && result.next !== requestedPage ? result.next : "";
            pagination.restart();
            if (result.warning) error = result.warning;
            if (!append) {
                if (titles.length) { if (!titles.some(t => sameTitle(t, selected))) selectTitle(titles[0]); }
                else { ++selectionGeneration; selectionDelay.stop(); selected = ({}); backgroundImage=""; detailLoading=false; artworkLoading=false; seasonsLoading=false; }
            }
        });
    }
    function selectTitle(title) {
        if (sameTitle(selected, title)) return;
        const generation = ++selectionGeneration;
        ++episodeGeneration;
        selected = title; backgroundImage = title.backdrop || ""; artworkReady = false; trailerIndex = 0; detailLoading = true; artworkLoading = true; seasonsLoading = kind === "tv"; detailError = "";
        personal = ({favorite:false,note:"",url:""}); seasons = []; episodes = []; episodeCatalogue.clear(); episodeNext = "";
        episodeLoading = false; tab = "overview"; links = []; spoiler = ""; extraLoading = false;
        selectionDelay.restart();
    }
    Timer { id: selectionDelay; interval: 90; onTriggered: root.hydrateSelection() }
    function refreshTitle() {
        ++selectionGeneration;
        selectionDelay.stop();
        detailLoading=true; artworkLoading=true; seasonsLoading=kind === "tv";
        detailError=""; artworkReady=false;
        hydrateSelection(true);
    }
    function hydrateSelection(refresh) {
        if (!selected.id) return;
        const title = selected;
        const generation = selectionGeneration;
        service.request("personal", {title:title}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (!failure) personal = result;
        });
        service.request("details", {title:title,refresh:!!refresh}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            detailLoading = false;
            if (failure) detailError = failure;
            else applyDetails(result);
        });
        service.request("artwork", {title:title,refresh:!!refresh}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            artworkLoading = false;
            if (failure) detailError = failure;
            if (!failure) {
                applyDetails(result.title); artworkReady = true;
                if (result.warnings.length) detailError = "Some extra artwork or ratings could not load. " + result.warnings.join(" ");
            }
        });
        if (kind === "tv") service.request("episodes", {title:title}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            seasonsLoading = false;
            if (!failure) { seasons = result.seasons; if (tab === "episodes") loadEpisodes(false); }
            else detailError = failure;
        });
    }
    function applyDetails(result) {
        const patch = Object.assign({}, result);
        if (!backgroundImage.toString() && patch.backdrop) backgroundImage = patch.backdrop;
        else if (backgroundImage.toString()) patch.backdrop = backgroundImage.toString();
        // Artwork responses own enriched fields; a slower details response must not revert them.
        if (artworkReady) ["backdrop","logo","ratings","cast","trailers"].forEach(key => delete patch[key]);
        selected = Object.assign({}, selected, patch);
    }
    function save(values) {
        const generation = selectionGeneration;
        service.request("save", {title:selected,values:values}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) detailError = failure; else personal = result;
        });
    }
    function play(episode) {
        if (!episode && kind === "tv" && episodeProviders[providerIndex]) {
            tab = "episodes";
            if (!episodes.length && !episodeLoading) loadEpisodes(false);
            return;
        }
        const generation = selectionGeneration;
        service.request("play", {title:selected,online:true,provider:providerIndex,season:episode ? episode.season : null,episode:episode ? episode.number : null}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) detailError = failure; else if (result.type === "direct") Quickshell.execDetached(result.command); else Qt.openUrlExternally(result.url);
        });
    }
    function loadEpisodes(append) {
        if (!selected.id || !seasons.length) return;
        const generation = ++episodeGeneration;
        const selection = selectionGeneration;
        episodeLoading = true;
        if (!append) { episodes = []; episodeCatalogue.clear(); }
        service.request("episodes", {title:selected,season:seasons[Math.max(0,seasonPicker.currentIndex)],page:append ? episodeNext : ""}, (result, failure) => {
            if (selection !== selectionGeneration || generation !== episodeGeneration) return;
            episodeLoading = false;
            if (failure) detailError = failure;
            else {
                episodes = (append ? episodes : []).concat(result.items);
                for (const episode of result.items) episodeCatalogue.append({payload:JSON.stringify(episode)});
                episodeNext = result.next;
            }
        });
    }
    function showPerson(person) {
        tab = "person"; personRole = "All"; const personRequest = ++personGeneration; extraLoading = true; personDetails = ({name:person.name});
        const generation = selectionGeneration;
        service.request("person", {person:person}, (result, failure) => {
            if (generation !== selectionGeneration || personRequest !== personGeneration) return;
            extraLoading = false;
            if (failure) detailError = failure; else personDetails = result;
        });
    }
    function extra(op) {
        tab = op; extraLoading = true;
        const generation = selectionGeneration;
        service.request(op, {title:selected}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            extraLoading = false;
            if (failure) detailError = failure;
            else if (op === "watch") links = result;
            else spoiler = result.text;
        });
    }
    Component.onCompleted: {
        service.request("init", {kind:kind}, (result, failure) => { if (failure) error = failure; else { providers = result.providers; episodeProviders = result.episodeProviders || []; gridMode = preferences.value("catalogue/grid", kind === "tv" ? true : preferences.value("movie/grid", false)); } });
        browse(false);
    }
    Timer { id: pagination; interval: 100; onTriggered: root.maybeLoadMore() }
    Timer { id: searchDelay; interval: 350; onTriggered: root.browse(false) }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Layout.fillWidth: true; Layout.minimumHeight: 46; Layout.preferredHeight: 46; Layout.maximumHeight: 46; spacing: 8
            W.Action { text: "Discover"; highlighted: !root.favorites; onClicked: { root.favorites = false; root.browse(false); } }
            W.Action { iconName: "star"; text: "Favorites"; highlighted: root.favorites; onClicked: { root.favorites = true; root.browse(false); } }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 0 }
            Flickable {
                id: inlineFilters; objectName: "inlineFilters"
                visible: root.filtersOpen && !root.favorites
                Layout.fillWidth: true; Layout.preferredWidth: filterFields.implicitWidth
                Layout.minimumWidth: 120; Layout.maximumWidth: filterFields.implicitWidth
                Layout.preferredHeight: 46
                clip: true; contentWidth: filterFields.implicitWidth; contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                W.WheelScroll { view: inlineFilters; horizontal: true }
                ScrollBar.horizontal: ScrollBar {}
                Row {
                    id: filterFields; spacing: 8
                    W.Choice { id: genre; width: 145; model: ["All genres","Action","Adventure","Animation","Biography","Comedy","Crime","Documentary","Drama","Family","Fantasy","History","Horror","Music","Mystery","Romance","Sci-Fi","Sport","Thriller","War","Western"]; Accessible.name: "Genre" }
                    W.Choice { id: sort; width: 150; model: ["Provider order","Popularity","Highest rating","Most votes","Newest release","Oldest release"]; Accessible.name: "Sort" }
                    W.Choice { id: country; objectName: "countryPicker"; width: 160; model: Countries.options; textRole: "name"; Accessible.name: "Country" }
                    W.SearchField { id: minYear; width: 90; placeholderText: "From year"; validator: IntValidator { bottom: 1870; top: 2200 } }
                    W.SearchField { id: maxYear; width: 90; placeholderText: "To year"; validator: IntValidator { bottom: 1870; top: 2200 } }
                    W.SearchField { id: rating; width: 95; placeholderText: "Min rating"; validator: DoubleValidator { bottom: 0; top: 10 } }
                    W.SearchField { id: votes; width: 95; placeholderText: "Min votes"; validator: IntValidator { bottom: 0 } }
                    W.Action { text: "Apply"; onClicked: { root.filters = {genre:genre.currentIndex ? genre.currentText : "",sort:["","popular","rating","votes","newest","oldest"][sort.currentIndex],country:Countries.options[country.currentIndex].code,minYear:minYear.text,maxYear:maxYear.text,rating:rating.text,votes:votes.text}; root.browse(false); } }
                    W.Action { text: "Reset"; onClicked: { genre.currentIndex=0; sort.currentIndex=0; country.currentIndex=0; minYear.clear(); maxYear.clear(); rating.clear(); votes.clear(); root.filters=({}); root.browse(false); } }
                }
            }
            W.SearchField {
                id: search; rightPadding: 42; visible: root.searchOpen; Layout.preferredWidth: Math.min(root.filtersOpen ? 280 : 460,root.width * 0.3)
                placeholderText: root.kind === "tv" ? "Search TV series…" : "Search movies…"
                onTextChanged: searchDelay.restart()
                W.IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; visible: search.text.length > 0; iconName: "x"; text: "Clear search"; onClicked: { search.clear(); search.forceActiveFocus(); } }
                onAccepted: { searchDelay.stop(); root.browse(false); }
            }
            Item {
                Layout.minimumWidth: 28; Layout.maximumWidth: 28; Layout.preferredHeight: 28
                BusyIndicator { anchors.fill: parent; running: root.loading; visible: running }
            }
            W.IconButton { objectName: "searchButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; highlighted: root.searchOpen; iconName: "search"; text: "Search " + (root.kind === "tv" ? "TV series" : "movies"); onClicked: { root.searchOpen = !root.searchOpen; if (root.searchOpen) search.forceActiveFocus(); else search.text = ""; } }
            W.IconButton { objectName: "filtersButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; iconName: "sliders-horizontal"; text: "Filters"; enabled: !root.favorites; highlighted: root.filtersOpen; onClicked: root.filtersOpen = !root.filtersOpen }
            W.IconButton { Layout.minimumWidth: 42; Layout.maximumWidth: 42; iconName: root.gridMode ? "panels-top-left" : "layout-grid"; text: root.gridMode ? "Show poster rail" : "Show grid"; onClicked: { root.gridMode = !root.gridMode; preferences.setValue("catalogue/grid",root.gridMode); } }
        }
        RowLayout {
            visible: !!root.error; Layout.fillWidth: true
            W.Label { text: root.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
            W.Action { text: "Retry"; onClicked: root.browse(false) }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            GridView {
                id: grid; objectName: "catalogueGrid"; visible: root.gridMode
                width: parent.width * 0.51; height: parent.height
                clip: true; model: catalogue
                cellWidth: width / Math.max(2,Math.floor(width/155)); cellHeight: cellWidth*1.5+48
                keyNavigationEnabled: true; keyNavigationWraps: false
                delegate: Poster {
                    required property string payload
                    readonly property var modelData: JSON.parse(payload)
                    required property int index
                    width: grid.cellWidth-8; height: grid.cellHeight-8; title: modelData
                    highlighted: root.sameTitle(root.selected, modelData)
                    onClicked: { grid.forceActiveFocus(); grid.currentIndex=index; root.selectTitle(modelData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameTitle(currentItem.title, root.selected)) root.selectTitle(currentItem.title)
                Keys.onReturnPressed: if (currentItem) root.selectTitle(currentItem.title)
                W.WheelScroll { objectName: "gridWheel"; view: grid; pixelsPerNotch: Math.max(360, grid.cellHeight * 1.25) }
                onContentYChanged: pagination.restart()
                ScrollBar.vertical: ScrollBar {}
            }
            ColumnLayout {
                id: detail; x: root.gridMode ? parent.width*0.55 : 16
                width: root.gridMode ? parent.width*0.45 : Math.min(parent.width*0.7,1000)
                height: root.gridMode ? parent.height : parent.height - Math.min(270,parent.height*0.38)
                visible: !!root.selected.id; spacing: 8
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: Math.max(72,Math.min(145,root.height*0.17))
                    W.CrossfadeImage { id: logo; anchors.fill: parent; source: root.selected.logo || ""; fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft; imageWidth: 900 }
                    W.Label { anchors.fill: parent; opacity: 1 - logo.imageOpacity; visible: opacity > 0; text: root.selected.title || ""; font.pixelSize: Math.min(48,root.width/25); font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 2; verticalAlignment: Text.AlignVCenter }
                }
                W.Label { Layout.fillWidth: true; text: [root.selected.year,root.selected.runtime ? root.selected.runtime + " min" : "",(root.selected.genres || []).join(" / ")].filter(Boolean).join("   ·   "); color: Theme.muted }
                Ratings { Layout.fillWidth: true; Layout.minimumHeight: 28; ratings: root.selected.ratings || []; title: root.selected }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    SplitButton { objectName: "onlineButton"; text: "Watch online"; options: root.providers; currentIndex: root.providerIndex; onTriggered: index => { root.providerIndex=index; root.play(null); } }
                    SplitButton { visible: root.trailers.length > 0; text: root.trailers.length === 1 ? "Trailer" : "Trailers"; options: root.trailers.map(t => t.title); currentIndex: root.trailerIndex; onTriggered: index => { root.trailerIndex=index; if (root.trailers[index]) Qt.openUrlExternally(root.trailers[index].url); } }
                    W.IconButton { iconName: root.personal.favorite ? "star-filled" : "star"; text: root.personal.favorite ? "Remove favorite" : "Add favorite"; onClicked: root.save({favorite:!root.personal.favorite}) }
                    W.IconButton { iconName: "refresh-cw"; text: "Refresh title"; onClicked: root.refreshTitle() }
                    BusyIndicator { objectName: "titleLoadingIndicator"; running: root.titleLoading; visible: running; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 2
                    W.Action { text: "Overview"; highlighted: root.tab === "overview"; onClicked: root.tab="overview" }
                    W.Action { text: "Cast"; highlighted: root.tab === "cast"; onClicked: root.tab="cast" }
                    W.Action { text: "Episodes"; visible: root.kind === "tv"; highlighted: root.tab === "episodes"; onClicked: { root.tab="episodes"; if (!root.episodes.length) root.loadEpisodes(false); } }
                    W.Action { text: "Watch"; highlighted: root.tab === "watch"; onClicked: root.extra("watch") }
                    W.Action { text: "Spoilers"; visible: root.kind === "movie"; highlighted: root.tab === "spoilers"; onClicked: root.extra("spoilers") }
                }
                W.Label { visible: !!root.detailError; Layout.fillWidth: true; text: root.detailError; color: Theme.danger; wrapMode: Text.Wrap; maximumLineCount: 2 }
                W.ScrollArea {
                    visible: !["cast","person","episodes"].includes(root.tab)
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width; spacing: 12
                        W.Label { visible: root.tab === "overview"; Layout.fillWidth: true; text: root.selected.plot || (root.detailLoading ? "Loading synopsis…" : "No synopsis available."); wrapMode: Text.Wrap; font.pixelSize: 16 }
                        W.Label { visible: root.tab === "overview"; Layout.fillWidth: true; text: (root.selected.countries || []).map(Countries.label).join(" / "); color: Theme.muted; wrapMode: Text.Wrap }
                        Repeater {
                            model: root.tab === "overview" ? [{label:"Directed by",people:root.directors},{label:"Written by",people:root.writers},{label:"Starring",people:root.stars}] : []
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true; visible: modelData.people.length > 0; spacing: 3
                                W.Label { text: modelData.label; color: Theme.muted }
                                Flow {
                                    Layout.fillWidth: true; spacing: 4
                                    Repeater { model: modelData.people; RowLayout {
                                        required property var modelData
                                        spacing: 0
                                        W.CrossfadeImage { source: modelData.image || ""; imageWidth: 84; Layout.preferredWidth: 36; Layout.preferredHeight: 48 }
                                        W.Action { text: modelData.name; enabled: !!modelData.id; onClicked: root.showPerson(modelData) }
                                    } }
                                }
                            }
                        }
                        Repeater { model: root.tab === "watch" ? root.links : []; W.Action { required property var modelData; text: modelData.name; onClicked: Qt.openUrlExternally(modelData.url) } }
                        W.Label { visible: root.tab === "watch" && !root.extraLoading && !root.links.length; text: "No watch links loaded."; color: Theme.muted }
                        W.Label { visible: root.tab === "spoilers"; Layout.fillWidth: true; text: root.spoiler; wrapMode: Text.Wrap }
                    }
                }
                ListView {
                    id: castView
                    visible: root.tab === "cast"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: visible ? root.cast : []
                    spacing: 8
                    W.WheelScroll { view: castView }
                    ScrollBar.vertical: ScrollBar {}
                    delegate: W.Action {
                        id: castRow
                        required property var modelData
                        width: castView.width; implicitHeight: Math.max(68,castText.implicitHeight+16)
                        text: modelData.name; enabled: !!modelData.id
                        onClicked: root.showPerson(modelData)
                        contentItem: RowLayout {
                            spacing: 12
                            W.CrossfadeImage { source: castRow.modelData.image || ""; imageWidth: 84; Layout.preferredWidth: 42; Layout.preferredHeight: 60 }
                            ColumnLayout {
                                id: castText; Layout.fillWidth: true
                                W.Label { text: castRow.modelData.name; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                W.Label { text: castRow.modelData.role || ""; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            }
                        }
                    }
                }
                GridView {
                    id: filmography; objectName: "filmography"
                    visible: root.tab === "person"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    cellWidth: width / Math.max(1,Math.floor(width/140)); cellHeight: cellWidth*1.5+48
                    model: visible ? root.personCredits.filter(t => root.personRole === "All" || (t.roles || []).includes(root.personRole)).sort((a,b) => Number(b.year || 0)-Number(a.year || 0)) : []
                    W.WheelScroll { view: filmography; pixelsPerNotch: Math.max(360, filmography.cellHeight*1.25) }
                    ScrollBar.vertical: ScrollBar {}
                    header: Column {
                        width: filmography.width; spacing: 12; bottomPadding: 16
                        W.Label { width: parent.width; text: root.personDetails.name || ""; font.pixelSize: 22; font.bold: true; wrapMode: Text.Wrap }
                        W.Label { width: parent.width; text: root.personDetails.biography || ""; wrapMode: Text.Wrap }
                        BusyIndicator { visible: root.extraLoading; running: visible }
                        Flow {
                            width: parent.width; spacing: 4
                            Repeater { model: root.personRoles; W.Action { required property string modelData; text: modelData; highlighted: root.personRole === modelData; onClicked: { root.personRole=modelData; filmography.positionViewAtBeginning(); } } }
                        }
                    }
                    delegate: Poster {
                        required property var modelData
                        width: filmography.cellWidth-8; height: filmography.cellHeight-8
                        title: modelData; onClicked: root.selectTitle(modelData)
                    }
                }
                ColumnLayout {
                    visible: root.tab === "episodes"
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                    W.Choice { id: seasonPicker; Layout.preferredWidth: 160; model: root.seasons.map(s => "Season " + s); onActivated: root.loadEpisodes(false); Accessible.name: "Season" }
                    ListView {
                        id: episodeView
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        model: root.tab === "episodes" ? episodeCatalogue : null
                        spacing: 8
                        W.WheelScroll { view: episodeView }
                        ScrollBar.vertical: ScrollBar {}
                        delegate: EpisodeRow {
                            required property string payload
                            width: episodeView.width; episode: JSON.parse(payload)
                            onClicked: root.play(episode)
                        }
                        footer: Column {
                            width: episodeView.width
                            BusyIndicator { visible: root.episodeLoading; running: visible }
                            W.Label { visible: !root.episodeLoading && !root.episodes.length; text: "No episodes available yet."; color: Theme.muted }
                            W.Action { visible: !!root.episodeNext; text: "More episodes"; enabled: !root.episodeLoading; onClicked: root.loadEpisodes(true) }
                        }
                    }
                }
            }
            ListView {
                id: rail; objectName: "catalogueRail"; visible: !root.gridMode
                anchors.bottom: parent.bottom; width: parent.width; height: Math.min(250,parent.height*0.36)
                orientation: ListView.Horizontal; spacing: 12; clip: true; model: catalogue
                keyNavigationEnabled: true; keyNavigationWraps: false
                delegate: Poster {
                    required property string payload
                    readonly property var modelData: JSON.parse(payload)
                    required property int index
                    width: (rail.height-42)/1.5; height: rail.height; title: modelData
                    highlighted: root.sameTitle(root.selected, modelData)
                    onClicked: { rail.forceActiveFocus(); rail.currentIndex=index; root.selectTitle(modelData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameTitle(currentItem.title, root.selected)) root.selectTitle(currentItem.title)
                Keys.onReturnPressed: if (currentItem) root.selectTitle(currentItem.title)
                onContentXChanged: pagination.restart()
                W.WheelScroll { view: rail; horizontal: true; pixelsPerNotch: 360 }
                ScrollBar.horizontal: ScrollBar {}
            }
            W.Label { anchors.centerIn: parent; visible: !root.titles.length; text: root.loading ? "Loading " + (root.kind === "tv" ? "TV series…" : "movies…") : root.error ? "" : root.favorites ? "No saved favorites yet." : "No matching titles."; color: Theme.muted }
        }
        Item { Layout.fillWidth: true; Layout.preferredHeight: 42 }
    }
}
