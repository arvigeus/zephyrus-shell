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
    objectName: "booksBrowser"
    property var host
    property var books: []
    property var selected: ({})
    property url backgroundImage: selected.coverSmall || selected.coverLarge || ""
    property real backgroundImageOpacity: 0.16
    property int backgroundImageWidth: 360
    property var personal: ({favorite: false})
    property var filters: ({})
    property string nextPage: ""
    property string error: ""
    property string detailError: ""
    property bool loading: true
    property bool detailLoading: false
    property bool favorites: false
    property bool localMode: false
    property var localFiles: []
    property bool searchOpen: false
    property bool filtersOpen: false
    property bool gridMode: false
    property int browseGeneration: 0
    property int selectionGeneration: 0
    property int authorGeneration: 0
    property int editionsGeneration: 0
    property string tab: "overview"
    property var author: ({})
    property var authorDetails: ({})
    property var authorWorks: []
    property string authorNext: ""
    property string authorError: ""
    property bool authorLoading: false
    property var editions: []
    property string editionsNext: ""
    property string editionsError: ""
    property bool editionsLoading: false
    property bool updatingCatalogue: false
    readonly property bool titleLoading: detailLoading
    readonly property string readingAction: selected.ebookAccess === "public" ? "Read on Open Library" : selected.ebookAccess === "borrowable" ? "Borrow on Open Library" : selected.ebookAccess === "printdisabled" ? "Preview on Open Library" : ""

    ListModel { id: catalogue }
    ListModel { id: authorCatalogue }
    Settings {
        id: preferences
        location: "file://" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/zephyrus-shell/books-ui.ini"
    }
    BooksService { id: service; onFailed: message => { root.error = message; root.loading = false; } }
    M.TorrentService { id: localService }

    W.DetailScrim {
        gridMode: root.gridMode
        opacity: 0.25
    }

    function activate() { (gridMode ? grid : rail).forceActiveFocus(); }
    function sameBook(a, b) { return !!(a && b && a.id && b.id && a.id === b.id); }
    function updateCatalogue(items, append) {
        updatingCatalogue = true;
        books = Catalogue.update(catalogue, books, items, append);
        updatingCatalogue = false;
    }
    function updateAuthorWorks(items, append) {
        authorWorks = Catalogue.update(authorCatalogue, authorWorks, items, append);
    }
    function updateBook(book) {
        if (!book || !book.id) return;
        const index = books.findIndex(item => item.id === book.id);
        if (index >= 0) {
            const next = books.slice(); next[index] = book; books = next;
            const row = Array.from({length: catalogue.count}, (_, i) => catalogue.get(i)).findIndex(item => item.key === book.id);
            if (row >= 0) catalogue.setProperty(row, "payload", JSON.stringify(book));
        }
        if (sameBook(selected, book)) selected = book;
    }
    function clearSelection() {
        ++selectionGeneration;
        detailDelay.stop();
        selected = ({}); personal = ({favorite: false}); detailLoading = false; detailError = "";
    }
    function chooseFirstIfNeeded() {
        if (books.length && !books.some(book => sameBook(book, selected))) selectBook(books[0]);
        else if (!books.length) clearSelection();
    }
    function browse(append, force) {
        if (localMode) {
            const generation = ++browseGeneration;
            loading = true; error = ""; nextPage = "";
            localService.request("local_list", {kind:"book"}, (result, failure) => {
                if (generation !== browseGeneration) return;
                loading = false;
                if (failure) { error = failure; return; }
                const query = search.text.trim().toLowerCase();
                updateCatalogue(result.filter(book => !query || book.title.toLowerCase().includes(query)), false);
                chooseFirstIfNeeded();
            });
            return;
        }
        if (append && (loading || !nextPage)) return;
        const offset = append ? Number(nextPage) : 0;
        const generation = ++browseGeneration;
        const args = {query: search.text, filters: filters, favorites: favorites, offset: offset, refresh: !!force};
        loading = true; error = "";
        if (!append) service.request("snapshot", args, (result, failure) => {
            if (generation !== browseGeneration || failure || !result) return;
            updateCatalogue(result.items || [], false);
            nextPage = result.next || "";
            chooseFirstIfNeeded();
            if (result.warning) error = result.warning;
        });
        service.request("browse", args, (result, failure) => {
            if (generation !== browseGeneration) return;
            loading = false;
            if (failure) { error = failure; return; }
            if (!result) { error = "No book results were returned."; return; }
            updateCatalogue(result.items || [], append);
            nextPage = result.next && result.next !== String(offset) ? result.next : "";
            pagination.restart();
            if (result.warning) error = result.warning;
            if (!append) chooseFirstIfNeeded();
        });
    }
    function selectBook(book) {
        if (!book || !book.id) return;
        if (sameBook(book, selected)) { if (tab === "author") tab = "overview"; return; }
        const generation = ++selectionGeneration;
        ++authorGeneration; ++editionsGeneration;
        detailDelay.stop();
        selected = book; personal = ({favorite: !!book.favorite});
        localFiles = [];
        detailLoading = true; detailError = ""; tab = "overview";
        author = ({}); authorDetails = ({}); authorWorks = []; authorCatalogue.clear(); authorNext = ""; authorError = ""; authorLoading = false;
        editions = []; editionsNext = ""; editionsError = ""; editionsLoading = false;
        service.request("personal", {book: book}, (result, failure) => {
            if (generation === selectionGeneration && !failure && result) personal = result;
        });
        localService.request("local_files", {title:Object.assign({}, book, {kind:"book"})}, (result, failure) => {
            if (generation === selectionGeneration && !failure) localFiles = result;
        });
        detailDelay.restart();
    }
    Timer {
        id: detailDelay
        interval: 170
        onTriggered: {
            if (!root.selected.id) return;
            const generation = root.selectionGeneration;
            service.request("details", {book: root.selected}, (result, failure) => {
                if (generation !== root.selectionGeneration) return;
                root.detailLoading = false;
                if (failure) root.detailError = failure;
                else if (result) {
                    root.selected = Object.assign({}, root.selected, result);
                    root.updateBook(root.selected);
                    if (result.warning) root.detailError = result.warning;
                }
            });
        }
    }
    function refreshBook() {
        if (!selected.id) return;
        const generation = ++selectionGeneration;
        detailLoading = true; detailError = "";
        service.request("details", {book: selected, refresh: true}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            detailLoading = false;
            if (failure) detailError = failure;
            else if (result) { selected = Object.assign({}, selected, result); updateBook(selected); if (result.warning) detailError = result.warning; }
        });
    }
    function saveFavorite(value) {
        if (!selected.id) return;
        const generation = selectionGeneration;
        const updated = Object.assign({}, selected, {favorite: !!value});
        selected = updated; personal = ({favorite: !!value}); updateBook(updated);
        service.request("save", {book: updated, favorite: !!value}, (result, failure) => {
            if (generation !== selectionGeneration) return;
            if (failure) { personal = ({favorite: !value}); selected = Object.assign({}, selected, {favorite: !value}); updateBook(selected); detailError = failure; }
            else if (result) personal = result;
            if (root.favorites && !value) root.browse(false);
        });
    }
    function showAuthor(person) {
        if (!person || !person.id) return;
        const generation = ++authorGeneration;
        author = Object.assign({}, person); authorDetails = ({name: person.name || "Unknown author"});
        authorWorks = []; authorCatalogue.clear(); authorNext = ""; authorError = ""; authorLoading = true; tab = "author";
        service.request("authorDetails", {author: author}, (result, failure) => {
            if (generation !== authorGeneration) return;
            if (failure) authorError = failure;
            else if (result) { authorDetails = result; if (result.warning) authorError = result.warning; }
        });
        loadAuthorWorks(false, generation);
    }
    function loadAuthorWorks(append, ownerGeneration) {
        if (authorLoading && append) return;
        const requested = append ? authorNext : "0";
        const generation = ownerGeneration === undefined ? authorGeneration : ownerGeneration;
        const offset = append ? Number(requested) : 0;
        authorLoading = true;
        service.request("authorWorks", {author: author, offset: offset}, (result, failure) => {
            if (generation !== authorGeneration) return;
            authorLoading = false;
            if (failure) { authorError = failure; return; }
            updateAuthorWorks(result.items || [], append);
            authorNext = result.next || "";
            if (result.warning) authorError = result.warning;
        });
    }
    function loadEditions(append) {
        if (!selected.id || (append && (editionsLoading || !editionsNext))) return;
        const generation = ++editionsGeneration;
        const offset = append ? Number(editionsNext) : 0;
        editionsLoading = true; editionsError = "";
        service.request("editions", {book: selected, offset: offset}, (result, failure) => {
            if (generation !== editionsGeneration) return;
            editionsLoading = false;
            if (failure) { editionsError = failure; return; }
            const byId = new Map((append ? editions : []).map(edition => [edition.id, edition]));
            for (const edition of result.items || []) byId.set(edition.id, edition);
            editions = Array.from(byId.values());
            editionsNext = result.next || "";
            if (result.warning) editionsError = result.warning;
        });
    }
    function maybeLoadMore() {
        if (loading || error || !nextPage || favorites || tab === "author") return;
        const nearEnd = gridMode
            ? grid.contentY + grid.height >= grid.contentHeight - grid.cellHeight * 2
            : (rail.contentX > rail.originX || rail.currentIndex >= books.length - 5) && rail.contentX + rail.width >= rail.contentWidth - rail.width * 0.5;
        if (nearEnd) browse(true, false);
    }
    function languageLabel(code) {
        const known = {eng:"English", spa:"Spanish", fre:"French", fra:"French", ger:"German", deu:"German", ita:"Italian", por:"Portuguese", jpn:"Japanese", chi:"Chinese", zho:"Chinese", rus:"Russian", ara:"Arabic", hin:"Hindi", kor:"Korean", vie:"Vietnamese", dut:"Dutch", nld:"Dutch", swe:"Swedish", nor:"Norwegian", dan:"Danish", fin:"Finnish", pol:"Polish", heb:"Hebrew", tur:"Turkish", ind:"Indonesian", cat:"Catalan", lat:"Latin", grc:"Ancient Greek", gre:"Greek"};
        return known[code] || code.toUpperCase();
    }
    function effectiveSortIndex() {
        const sorts = ["trending", "relevance", "newest", "oldest"];
        const saved = sorts.indexOf(root.filters.sort || "");
        return saved >= 0 ? saved : (search.text.trim().length ? 1 : 0);
    }
    function readingUrl() { return selected.openLibraryUrl || (selected.id ? "https://openlibrary.org/works/" + selected.id : ""); }

    Component.onCompleted: {
        gridMode = preferences.value("catalogue/grid", false);
        localService.request("local_list", {kind:"book"}, (result, failure) => {
            localMode = !failure && !!result && result.length > 0;
            browse(false, false);
        });
    }
    onGridModeChanged: { activate(); pagination.restart(); }
    Timer { id: pagination; interval: 120; onTriggered: root.maybeLoadMore() }
    Timer { id: searchDelay; interval: 350; onTriggered: root.browse(false, false) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            Layout.fillWidth: true; Layout.minimumHeight: 46; Layout.preferredHeight: 46; Layout.maximumHeight: 46; spacing: 8
            W.Action { iconName: "folder-open"; text: "Local"; highlighted: root.localMode; onClicked: { root.localMode = true; root.favorites = false; root.browse(false, false); } }
            W.Action { iconName: "globe"; text: "Discover"; highlighted: !root.localMode && !root.favorites; onClicked: { root.localMode = false; root.favorites = false; root.browse(false, false); } }
            W.Action { iconName: "star"; text: "Favorites"; highlighted: !root.localMode && root.favorites; onClicked: { root.localMode = false; root.favorites = true; root.browse(false, false); } }
            Item { Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 0 }
            Flickable {
                id: inlineFilters; objectName: "inlineFilters"
                visible: root.filtersOpen && !root.favorites && !root.localMode
                Layout.fillWidth: true; Layout.preferredWidth: filterFields.implicitWidth
                Layout.minimumWidth: 110; Layout.maximumWidth: filterFields.implicitWidth
                Layout.preferredHeight: 46
                clip: true; contentWidth: filterFields.implicitWidth; contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                W.WheelScroll { view: inlineFilters; horizontal: true }
                ScrollBar.horizontal: ScrollBar {}
                Row {
                    id: filterFields; spacing: 8
                    W.SearchField { id: subjectFilter; width: 170; placeholderText: "Subject"; Accessible.name: "Filter by subject" }
                    W.SearchField { id: languageFilter; width: 105; placeholderText: "Language · eng"; maximumLength: 3; Accessible.name: "Filter by language code" }
                    W.Choice { id: sortFilter; width: 138; model: ["Trending", "Relevance", "Newest first", "Oldest first"]; Accessible.name: "Sort books" }
                    W.SearchField {
                        id: minYear; width: 84; placeholderText: "From year"
                        validator: IntValidator { bottom: 1000; top: 2200 }
                        Accessible.name: "First published from year"
                    }
                    W.SearchField {
                        id: maxYear; width: 84; placeholderText: "To year"
                        validator: IntValidator { bottom: 1000; top: 2200 }
                        Accessible.name: "First published through year"
                    }
                    W.Action { text: "Apply"; onClicked: { root.filters = {subject:subjectFilter.text,language:languageFilter.text,sort:["trending","relevance","newest","oldest"][sortFilter.currentIndex],minYear:minYear.text,maxYear:maxYear.text}; root.browse(false, false); } }
                    W.Action { text: "Reset"; onClicked: { subjectFilter.clear(); languageFilter.clear(); root.filters=({}); sortFilter.currentIndex=root.effectiveSortIndex(); minYear.clear(); maxYear.clear(); root.browse(false, false); } }
                }
            }
            W.SearchField {
                id: search; objectName: "bookSearch"; rightPadding: 42; visible: root.searchOpen
                Layout.preferredWidth: Math.min(Theme.catalogueSearchWidth, root.width * 0.30)
                placeholderText: "Search books, authors, ISBNs…"
                Accessible.name: "Search books, authors, and ISBNs"
                onTextChanged: searchDelay.restart()
                W.IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; visible: search.text.length > 0; iconName: "x"; text: "Clear book search"; onClicked: { search.clear(); search.forceActiveFocus(); } }
                onAccepted: { searchDelay.stop(); root.browse(false, false); }
            }
            Item { Layout.minimumWidth: 28; Layout.maximumWidth: 28; Layout.preferredHeight: 28; BusyIndicator { anchors.fill: parent; running: root.loading; visible: running } }
            W.IconButton { objectName: "searchButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; highlighted: root.searchOpen; iconName: "search"; text: root.searchOpen ? "Close book search" : "Search books"; onClicked: { root.searchOpen = !root.searchOpen; if (root.searchOpen) search.forceActiveFocus(); else search.text = ""; } }
            W.IconButton { objectName: "filtersButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; iconName: "sliders-horizontal"; text: "Book filters"; enabled: !root.favorites && !root.localMode; highlighted: root.filtersOpen; onClicked: { root.filtersOpen = !root.filtersOpen; if (root.filtersOpen) sortFilter.currentIndex = root.effectiveSortIndex(); } }
            W.IconButton { objectName: "layoutButton"; Layout.minimumWidth: 42; Layout.maximumWidth: 42; iconName: root.gridMode ? "panels-top-left" : "layout-grid"; text: root.gridMode ? "Show cover rail" : "Show cover grid"; onClicked: { root.gridMode = !root.gridMode; preferences.setValue("catalogue/grid", root.gridMode); } }
        }
        RowLayout {
            visible: !!root.error; Layout.fillWidth: true
            W.Label { text: root.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
            W.Action { text: "Retry"; onClicked: root.browse(false, true) }
        }
        Item {
            id: content; Layout.fillWidth: true; Layout.fillHeight: true
            GridView {
                id: grid; objectName: "catalogueGrid"; visible: root.gridMode
                x: 0; y: 0; width: parent.width * 0.51; height: parent.height
                clip: true; model: catalogue
                cellWidth: width / Math.max(2, Math.floor(width / 155)); cellHeight: cellWidth * 1.5 + 48
                keyNavigationEnabled: true; keyNavigationWraps: false
                delegate: BookCard {
                    required property string payload
                    readonly property var modelData: JSON.parse(payload)
                    required property int index
                    width: grid.cellWidth - 8; height: grid.cellHeight - 8; book: modelData
                    highlighted: root.sameBook(root.selected, modelData)
                    onClicked: { grid.forceActiveFocus(); grid.currentIndex = index; root.selectBook(modelData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameBook(currentItem.book, root.selected)) root.selectBook(currentItem.book)
                Keys.onReturnPressed: if (currentItem) root.selectBook(currentItem.book)
                Keys.onEnterPressed: if (currentItem) root.selectBook(currentItem.book)
                W.WheelScroll { objectName: "gridWheel"; view: grid; pixelsPerNotch: Math.max(360, grid.cellHeight * 1.25) }
                onContentYChanged: pagination.restart()
                ScrollBar.vertical: ScrollBar {}
            }
            ColumnLayout {
                id: detail
                x: root.gridMode ? parent.width * 0.54 : 16
                y: 0
                width: root.gridMode ? parent.width * 0.46 - 12 : parent.width - 32
                height: root.gridMode ? parent.height : parent.height - Math.min(270, parent.height * 0.36) - 12
                visible: !!root.selected.id && root.tab !== "author"
                spacing: 8
                RowLayout {
                    id: detailHero
                    objectName: "detailHero"
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Math.max(Math.min(root.gridMode ? 228 : 292, Math.max(178, detail.height * 0.44)), detailText.implicitHeight)
                    Layout.maximumHeight: Math.max(Math.min(root.gridMode ? 228 : 292, Math.max(178, detail.height * 0.44)), detailText.implicitHeight)
                    spacing: 16
                    Item {
                        Layout.preferredWidth: Math.min(root.gridMode ? 148 : 210, detail.width * 0.34)
                        Layout.fillHeight: true
                        Rectangle { anchors.fill: parent; color: Theme.surface; radius: 7; border.color: Theme.border; border.width: 1 }
                        W.CrossfadeImage {
                            id: detailCoverFallback
                            anchors.fill: parent; anchors.margins: 4
                            source: root.selected.coverSmall || ""
                            imageWidth: 500
                            fillMode: Image.PreserveAspectFit
                            visible: hasImage
                            resetOnSourceChange: true
                        }
                        W.CrossfadeImage {
                            id: detailCover
                            anchors.fill: parent; anchors.margins: 4
                            source: root.selected.coverLarge || root.selected.coverSmall || ""
                            fillMode: Image.PreserveAspectFit; imageWidth: 900
                            resetOnSourceChange: true
                        }
                        Column {
                            anchors.centerIn: parent; width: parent.width - 20; spacing: 10; visible: !detailCover.hasImage && detailCoverFallback.status !== Image.Ready
                            W.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 32; height: 32; name: "book-open"; opacity: 0.55 }
                            W.Label { width: parent.width; text: root.selected.title || ""; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 5 }
                        }
                    }
                    ColumnLayout {
                        id: detailText
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
                        W.Label { Layout.fillWidth: true; text: root.selected.title || ""; font.family: Theme.font; font.pixelSize: Theme.sp(Math.min(32, detail.width / 22)); font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 3 }
                        Flow {
                            Layout.fillWidth: true; spacing: 3
                            Repeater {
                                model: root.selected.authors || []
                                W.Action { required property var modelData; objectName: modelData.id ? "authorLink-" + modelData.id : ""; text: modelData.name || "Unknown author"; enabled: !!modelData.id; Accessible.name: "Open author " + text; onClicked: root.showAuthor(modelData) }
                            }
                            W.Label { visible: !(root.selected.authors || []).length; text: "Author unknown"; color: Theme.muted }
                        }
                        W.Label {
                            Layout.fillWidth: true; color: Theme.muted; wrapMode: Text.Wrap; maximumLineCount: 2
                            text: [root.selected.firstPublishYear || "", root.selected.editionCount ? root.selected.editionCount + " editions" : "", root.selected.languages && root.selected.languages.length ? root.selected.languages.slice(0,3).map(root.languageLabel).join(" / ") : ""].filter(Boolean).join("   ·   ")
                        }
                        W.Label {
                            Layout.fillWidth: true; color: Theme.muted; visible: !!root.selected.ratingCount
                            text: root.selected.ratingAverage !== null && root.selected.ratingAverage !== undefined ? root.selected.ratingAverage.toFixed(1) + " / 5   ·   " + Number(root.selected.ratingCount || 0).toLocaleString() + " ratings" : Number(root.selected.ratingCount || 0).toLocaleString() + " ratings"
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 6
                            W.IconButton { visible: root.localFiles.length > 0; iconName: "folder-open"; text: "Open local book"; onClicked: External.launch(["xdg-open", root.localFiles[0].path], root.host) }
                            W.IconButton {
                                objectName: "openLibraryButton"
                                iconName: "book-open"
                                text: root.readingAction || "Open in Open Library"
                                Accessible.name: text
                                onClicked: Browser.open(root.readingUrl(), "books", "", root.host)
                            }
                            W.IconButton { objectName: "favoriteButton"; iconName: root.personal.favorite ? "star-filled" : "star"; text: root.personal.favorite ? "Remove from Favorites" : "Add to Favorites"; onClicked: root.saveFavorite(!root.personal.favorite) }
                            W.IconButton { iconName: "refresh-cw"; text: "Refresh book details"; onClicked: root.refreshBook() }
                            BusyIndicator { objectName: "titleLoadingIndicator"; running: root.titleLoading; visible: running; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 2
                            W.Action { text: "Overview"; highlighted: root.tab === "overview"; onClicked: root.tab = "overview" }
                            W.Action { objectName: "editionsTab"; text: "Editions"; highlighted: root.tab === "editions"; onClicked: { root.tab = "editions"; if (!root.editions.length) root.loadEditions(false); } }
                            W.Action { text: "Find"; highlighted: root.tab === "torrent"; onClicked: root.tab = "torrent" }
                        }
                    }
                }
                RowLayout {
                    visible: !!root.detailError; Layout.fillWidth: true
                    W.Label { text: root.detailError; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
                    W.Action { text: "Retry details"; onClicked: root.refreshBook() }
                }
                W.ScrollArea {
                    id: overview; visible: root.tab === "overview"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width; spacing: 10
                        W.Label {
                            objectName: "bookDescription"; Layout.fillWidth: true
                            text: root.selected.description || root.selected.first_sentence || (root.detailLoading ? "Loading synopsis…" : "No synopsis available.")
                            wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.sp(15)
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 5; visible: (root.selected.subjects || []).length > 0
                            Repeater {
                                model: (root.selected.subjects || []).slice(0, 10)
                                W.Action {
                                    required property string modelData
                                    text: modelData
                                    Accessible.name: "Filter by subject " + modelData
                                    onClicked: {
                                        root.filters = Object.assign({}, root.filters, {subject: modelData});
                                        subjectFilter.text = modelData;
                                        root.browse(false, false);
                                    }
                                }
                            }
                            W.Label { visible: (root.selected.subjectCount || 0) > 10; text: "+" + (root.selected.subjectCount - 10) + " more"; color: Theme.muted }
                        }
                        W.Label {
                            Layout.fillWidth: true; color: Theme.muted; wrapMode: Text.Wrap
                            visible: (root.selected.languages || []).length > 0
                            text: "Languages: " + (root.selected.languages || []).map(root.languageLabel).join(", ")
                        }
                        W.Label { Layout.fillWidth: true; text: "Open Library does not list a synopsis or complete metadata for every work."; color: Theme.muted; wrapMode: Text.Wrap; visible: !root.detailLoading && !root.selected.description && !root.selected.first_sentence && !(root.selected.subjects || []).length }
                    }
                }
                M.TorrentSearch {
                    visible: root.tab === "torrent"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    title: Object.assign({}, root.selected, {kind:"book",year:root.selected.firstPublishYear || "",author:(root.selected.authors || [])[0] ? root.selected.authors[0].name : ""})
                    onImported: {
                        localService.request("local_files", {title:Object.assign({}, root.selected, {kind:"book"})}, (result, failure) => { if (!failure) root.localFiles = result; });
                        if (root.localMode) root.browse(false, false);
                    }
                }
                ColumnLayout {
                    id: editionPane; visible: root.tab === "editions"
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        W.Label { Layout.fillWidth: true; text: root.selected.editionCount ? root.selected.editionCount + " editions" : "Editions"; font.bold: true }
                        BusyIndicator { visible: root.editionsLoading; running: visible; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                    }
                    W.Label { visible: !!root.editionsError; Layout.fillWidth: true; text: root.editionsError; color: Theme.danger; wrapMode: Text.Wrap }
                    ListView {
                        id: editionList; objectName: "editionList"
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                        model: root.tab === "editions" ? root.editions : []
                        W.WheelScroll { view: editionList }
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Item {
                            id: editionRow
                            required property var modelData
                            width: editionList.width; height: Math.max(76, editionContent.implicitHeight + 12)
                            Accessible.name: [modelData.title, modelData.year, (modelData.languages || []).map(root.languageLabel).join(", "), (modelData.publishers || []).join(", "), (modelData.isbn || []).join(", ")].filter(Boolean).join(". ")
                            RowLayout {
                                anchors.fill: parent; spacing: 10
                                Rectangle { Layout.preferredWidth: 44; Layout.preferredHeight: 62; color: Theme.surface; radius: 3
                                    W.CrossfadeImage { anchors.fill: parent; anchors.margins: 2; source: editionRow.modelData.cover || ""; fillMode: Image.PreserveAspectFit; imageWidth: 100 }
                                }
                                ColumnLayout {
                                    id: editionContent; Layout.fillWidth: true; spacing: 3
                                    W.Label { Layout.fillWidth: true; text: editionRow.modelData.title; font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
                                    W.Label { Layout.fillWidth: true; color: Theme.muted; wrapMode: Text.Wrap
                                        text: [editionRow.modelData.year || editionRow.modelData.publishDate, (editionRow.modelData.languages || []).map(root.languageLabel).join(" / "), (editionRow.modelData.publishers || []).join(", "), editionRow.modelData.format, editionRow.modelData.pages ? editionRow.modelData.pages + " pages" : ""].filter(Boolean).join("   ·   ")
                                    }
                                    W.Label { Layout.fillWidth: true; color: Theme.muted; text: "ISBN " + (editionRow.modelData.isbn || []).join(" · "); visible: (editionRow.modelData.isbn || []).length > 0; wrapMode: Text.Wrap }
                                }
                            }
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                        }
                        footer: ColumnLayout {
                            width: editionList.width; spacing: 6
                            W.Label { visible: !root.editionsLoading && !root.editionsError && !root.editions.length; text: "No edition records are available for this work."; color: Theme.muted }
                            W.Action { visible: !!root.editionsNext; enabled: !root.editionsLoading; text: root.editionsLoading ? "Loading editions…" : "Load more editions"; onClicked: root.loadEditions(true) }
                        }
                    }
                }
            }
            ColumnLayout {
                id: authorPane
                x: root.gridMode ? parent.width * 0.54 : 16
                y: 0
                width: root.gridMode ? parent.width * 0.46 - 12 : parent.width - 32
                height: root.gridMode ? parent.height : parent.height - Math.min(270, parent.height * 0.36) - 12
                visible: root.tab === "author"
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 112; spacing: 12
                    W.IconButton { iconName: "chevron-left"; text: "Back to book"; Accessible.name: "Back to selected book"; onClicked: root.tab = "overview" }
                    Rectangle {
                        Layout.preferredWidth: 78; Layout.preferredHeight: 96; color: Theme.surface; radius: 5
                        W.CrossfadeImage { anchors.fill: parent; anchors.margins: 2; source: root.authorDetails.image || ""; fillMode: Image.PreserveAspectFit; imageWidth: 180 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        W.Label { Layout.fillWidth: true; text: root.authorDetails.name || root.author.name || "Unknown author"; font.family: Theme.font; font.pixelSize: Theme.sp(23); font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
                        W.Label { Layout.fillWidth: true; text: [root.authorDetails.birthDate, root.authorDetails.deathDate ? "– " + root.authorDetails.deathDate : ""].filter(Boolean).join("   ·   "); color: Theme.muted; wrapMode: Text.Wrap }
                        BusyIndicator { visible: root.authorLoading; running: visible; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                    }
                }
                W.Label { visible: !!root.authorError; Layout.fillWidth: true; text: root.authorError; color: Theme.danger; wrapMode: Text.Wrap; maximumLineCount: 2 }
                W.ScrollArea {
                    Layout.fillWidth: true; Layout.preferredHeight: Math.min(112, authorPane.height * 0.27); clip: true
                    contentWidth: availableWidth
                    W.Label { width: parent.width; text: root.authorDetails.biography || (root.authorLoading ? "Loading biography…" : "No biography available."); wrapMode: Text.Wrap }
                }
                W.Label { text: "Other works"; font.bold: true }
                GridView {
                    id: authorGrid; objectName: "authorWorksGrid"
                    activeFocusOnTab: true
                    Keys.onReturnPressed: if (currentItem) root.selectBook(currentItem.book)
                    Keys.onEnterPressed: if (currentItem) root.selectBook(currentItem.book)
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: authorCatalogue
                    cellWidth: width / Math.max(2, Math.floor(width / 145)); cellHeight: cellWidth * 1.5 + 48
                    keyNavigationEnabled: true; keyNavigationWraps: false
                    delegate: BookCard {
                        required property string payload
                        readonly property var modelData: JSON.parse(payload)
                        required property int index
                        highlighted: authorGrid.activeFocus && authorGrid.currentIndex === index
                        width: authorGrid.cellWidth - 8; height: authorGrid.cellHeight - 8; book: modelData
                        onClicked: root.selectBook(modelData)
                    }
                    W.WheelScroll { view: authorGrid; pixelsPerNotch: Math.max(360, authorGrid.cellHeight * 1.25) }
                    ScrollBar.vertical: ScrollBar {}
                    footer: W.Action { visible: !!root.authorNext; enabled: !root.authorLoading; text: root.authorLoading ? "Loading works…" : "Load more works"; onClicked: root.loadAuthorWorks(true) }
                }
            }
            ListView {
                id: rail; objectName: "catalogueRail"; visible: !root.gridMode && root.tab !== "author"
                anchors.bottom: parent.bottom; width: parent.width; height: Math.min(250, parent.height * 0.36)
                orientation: ListView.Horizontal; spacing: 12; clip: true; model: catalogue
                keyNavigationEnabled: true; keyNavigationWraps: false
                delegate: BookCard {
                    required property string payload
                    readonly property var modelData: JSON.parse(payload)
                    required property int index
                    width: Math.min(152, (rail.height - 42) / 1.45); height: rail.height; book: modelData
                    highlighted: root.sameBook(root.selected, modelData)
                    onClicked: { rail.forceActiveFocus(); rail.currentIndex = index; root.selectBook(modelData); }
                }
                onCurrentItemChanged: if (!root.updatingCatalogue && activeFocus && currentItem && !root.sameBook(currentItem.book, root.selected)) root.selectBook(currentItem.book)
                Keys.onReturnPressed: if (currentItem) root.selectBook(currentItem.book)
                Keys.onEnterPressed: if (currentItem) root.selectBook(currentItem.book)
                onContentXChanged: pagination.restart()
                W.WheelScroll { view: rail; horizontal: true; pixelsPerNotch: 360 }
                ScrollBar.horizontal: ScrollBar {}
            }
            W.Label {
                anchors.centerIn: parent; width: Math.min(420, parent.width - 56); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                visible: !root.books.length
                text: root.loading ? "Loading books…" : root.error ? "" : root.localMode ? "No local books yet." : root.favorites ? "No saved favorites yet." : "No books match this search."
                color: Theme.muted
            }
        }
        Item { Layout.fillWidth: true; Layout.preferredHeight: 42 }
    }
}
