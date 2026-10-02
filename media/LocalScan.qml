import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets" as W

ColumnLayout {
    id: root
    required property string kind
    property string error: ""
    property string info: ""
    property bool scanning: false
    property bool matching: false
    property int lookupGeneration: 0
    property var review: []
    property var current: ({})
    property var matches: []
    signal imported()
    spacing: 10
    TorrentService { id: service; onFailed: message => root.error = message }

    function scan() {
        if (scanning) return;
        ++lookupGeneration; scanning = true; matching = false; error = ""; info = ""; review = []; current = ({}); matches = [];
        service.request("scan", {kind:kind,path:pathField.text.trim()}, (result, failure) => {
            scanning = false;
            if (failure) { error = failure; return; }
            review = result.review;
            info = result.imported.length + " added to Local; " + result.review.length
                + " need a catalogue match." + (result.limited ? " Scan stopped after 500 files." : "")
                + (result.warning ? " " + result.warning : "");
            if (result.imported.length) imported();
        });
    }
    function choose(item) {
        ++lookupGeneration; current = item; matches = []; matching = false; error = "";
        lookup.text = kind === "music" ? [item.guess.artist, item.guess.title].filter(Boolean).join(" ")
            : item.guess.title || "";
        seasonField.text = item.guess.season === undefined ? "" : String(item.guess.season);
        episodeField.text = item.guess.episode === undefined ? "" : String(item.guess.episode);
        dateField.text = item.guess.releaseDate || "";
        findMatches();
    }
    function episodeLabel(item) {
        const parsed = item.guess || {};
        if (kind !== "tv") return "";
        const code = parsed.season === undefined || parsed.episode === undefined ? ""
            : "S" + String(parsed.season).padStart(2, "0") + "E" + String(parsed.episode).padStart(2, "0");
        return [code, parsed.episodeTitle].filter(Boolean).join(" · ");
    }
    function findMatches() {
        if (!current.token || !lookup.text.trim()) return;
        const token = current.token;
        const generation = ++lookupGeneration;
        matching = true; matches = [];
        service.request("scan_lookup", {token:token,query:lookup.text.trim()}, (result, failure) => {
            if (current.token !== token || generation !== lookupGeneration) return;
            matching = false;
            if (failure) error = failure; else matches = result;
        });
    }
    function importMatch(title) {
        const args = {token:current.token,title:title};
        if (kind === "tv") {
            if (!seasonField.text || !episodeField.text) {
                error = "Confirm the season and episode number first."; return;
            }
            args.season = Number(seasonField.text); args.episode = Number(episodeField.text);
        }
        if (kind === "music" && dateField.text.trim()) args.releaseDate = dateField.text.trim();
        service.request("scan_import", args, (result, failure) => {
            if (failure) { error = failure; return; }
            review = review.filter(item => !(result.removedTokens || [current.token]).includes(item.token));
            current = ({}); matches = [];
            info = "Added " + title.title + " to Local. " + review.length + " files still need a match.";
            imported();
        });
    }

    W.Label { Layout.fillWidth: true; text: "Scan completed qBittorrent downloads and your " + (kind === "movie" ? "Movies" : kind === "tv" ? "Series" : "Local") + " folder. Choose a folder or file only to scan somewhere else. Exact catalogue matches are organized automatically; other files wait for review."; wrapMode: Text.Wrap; color: Theme.muted }
    RowLayout {
        Layout.fillWidth: true
        W.SearchField { id: pathField; Layout.fillWidth: true; placeholderText: "Optional folder or file"; onAccepted: root.scan() }
        W.Action { iconName: "file-search-corner"; text: "Scan"; enabled: !root.scanning; onClicked: root.scan() }
        W.BusySpinner { running: root.scanning; visible: running; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
    }
    W.Label { visible: !!root.error; Layout.fillWidth: true; text: root.error; color: Theme.danger; wrapMode: Text.Wrap }
    W.Label { visible: !!root.info; Layout.fillWidth: true; text: root.info; color: Theme.muted; wrapMode: Text.Wrap }
    RowLayout {
        visible: !!root.current.token; Layout.fillWidth: true
        W.Action { iconName: "arrow-left"; text: "All scan results"; onClicked: { ++root.lookupGeneration; root.current = ({}); root.matches = []; root.matching = false; } }
        W.Label { Layout.fillWidth: true; text: root.current.path || ""; elide: Text.ElideMiddle }
    }
    RowLayout {
        visible: !!root.current.token; Layout.fillWidth: true
        W.SearchField { id: lookup; Layout.fillWidth: true; placeholderText: "Find catalogue title"; onAccepted: root.findMatches() }
        W.IconButton { iconName: "search"; text: "Search catalogue"; onClicked: root.findMatches() }
        W.BusySpinner { running: root.matching; visible: running; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
        W.SearchField { id: seasonField; visible: root.kind === "tv"; Layout.preferredWidth: 80; placeholderText: "Season"; validator: IntValidator { bottom: 0; top: 99 } }
        W.SearchField { id: episodeField; visible: root.kind === "tv"; Layout.preferredWidth: 80; placeholderText: "Episode"; validator: IntValidator { bottom: 1; top: 999 } }
        W.SearchField { id: dateField; visible: root.kind === "music"; Layout.preferredWidth: 150; placeholderText: "YYYY-MM-DD" }
    }
    ListView {
        id: matchList
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        model: root.current.token ? root.matches : root.review
        spacing: 6
        W.WheelScroll { view: matchList }
        ScrollBar.vertical: ScrollBar {}
        delegate: W.Action {
            required property var modelData
            width: ListView.view.width
            text: root.current.token
                ? modelData.title + (root.kind === "music" ? " — " + modelData.artist + " · " + modelData.album
                    : " (" + (modelData.year || "?") + ")")
                    + (root.kind === "tv" && modelData.episodeLabel ? " · " + modelData.episodeLabel : "")
                : (modelData.guess.title || "Unknown")
                    + (root.episodeLabel(modelData) ? " · " + root.episodeLabel(modelData) : "")
                    + " · " + modelData.path
            onClicked: root.current.token ? root.importMatch(modelData) : root.choose(modelData)
        }
    }
}
