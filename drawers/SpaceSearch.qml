import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../core"
import "../widgets"

Item {
    id: root
    property string initialQuery: ""
    property bool catalogReady: false
    property var applications: DesktopEntries.applications.values.filter(app => !app.noDisplay)
    property var spaces: Modules.entries
    readonly property alias query: search.text
    readonly property alias currentIndex: results.currentIndex
    readonly property var matches: {
        const query = search.text.trim().toLowerCase();
        if (!query) return [];
        const words = query.split(/\s+/);
        const candidates = applications.map(app => ({kind: "app", entry: app,
            terms: app.name + " " + (app.genericName || "") + " " + (app.keywords || []).join(" ")}))
            .concat(spaces.map(space => ({kind: "space", entry: space, terms: space.name})));
        return candidates.filter(item => words.every(word => item.terms.toLowerCase().includes(word)))
            .sort((a, b) => {
                function rank(item) {
                    const name = item.entry.name.toLowerCase();
                    return name === query ? 0 : name.startsWith(query) ? 1 : 2;
                }
                return rank(a) - rank(b) || (a.kind === b.kind ? 0 : a.kind === "app" ? -1 : 1)
                    || a.entry.name.localeCompare(b.entry.name);
            });
    }
    function activateResult(index) {
        if (index < 0 || index >= matches.length) return;
        const result = matches[index];
        if (result.kind === "space") ShellState.openPlugin(result.entry.id);
        else { result.entry.execute(); ShellState.showDesktop(); }
    }
    function moveSelection(delta) {
        if (!matches.length) return;
        results.currentIndex = Math.max(0, Math.min(matches.length - 1, results.currentIndex + delta));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    Component.onCompleted: {
        search.text = initialQuery;
        search.forceActiveFocus();
        Qt.callLater(() => root.catalogReady = true);
    }
    Keys.onEscapePressed: ShellState.dismissPanel()
    Rectangle { anchors.fill: parent; color: "#80000000" }
    // Four outside regions leave the search card's input area untouched.
    MouseArea { width: root.width; height: card.y; acceptedButtons: Qt.AllButtons; onClicked: ShellState.dismissPanel() }
    MouseArea { y: card.y + card.height; width: root.width; height: root.height - y; acceptedButtons: Qt.AllButtons; onClicked: ShellState.dismissPanel() }
    MouseArea { y: card.y; width: card.x; height: card.height; acceptedButtons: Qt.AllButtons; onClicked: ShellState.dismissPanel() }
    MouseArea { x: card.x + card.width; y: card.y; width: root.width - x; height: card.height; acceptedButtons: Qt.AllButtons; onClicked: ShellState.dismissPanel() }
    Rectangle {
        id: card
        x: (root.width - width) / 2
        y: Math.min(root.height * 0.18, 160)
        width: Math.min(620, root.width - 40)
        height: Math.min(content.implicitHeight + 32, root.height - y - 20)
        radius: Theme.controlRadius
        color: Theme.background
        border.color: Theme.border
        ColumnLayout {
            id: content
            anchors.fill: parent; anchors.margins: 16; spacing: 12
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Icon { name: "search"; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                SearchField {
                    id: search
                    objectName: "spacesSearchField"
                    Layout.fillWidth: true
                    placeholderText: "Search applications and spaces…"
                    onTextChanged: results.currentIndex = root.matches.length ? 0 : -1
                    onAccepted: root.activateResult(results.currentIndex)
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onEscapePressed: ShellState.dismissPanel()
                }
                IconButton { iconName: "x"; text: "Close search"; onClicked: ShellState.dismissPanel() }
            }
            ListView {
                id: results
                objectName: "spacesSearchResults"
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredHeight: Math.min(7, count) * 58
                model: root.catalogReady ? root.matches : []
                clip: true; spacing: 4
                onModelChanged: currentIndex = count ? 0 : -1
                WheelScroll { view: results }
                delegate: Action {
                    id: resultButton
                    required property var modelData
                    required property int index
                    width: results.width; height: 54
                    text: modelData.entry.name
                    ToolTip.visible: false
                    highlighted: results.currentIndex === index
                    contentItem: RowLayout {
                        spacing: 12
                        Item {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            AppIcon { anchors.fill: parent; visible: resultButton.modelData.kind === "app"; icon: visible ? resultButton.modelData.entry.icon : "" }
                            Icon { anchors.centerIn: parent; width: 24; height: 24; visible: resultButton.modelData.kind === "space"; name: visible ? resultButton.modelData.entry.icon : "" }
                        }
                        Label { text: resultButton.text; Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight }
                        Label { text: resultButton.modelData.kind === "app" ? "Application" : "Space"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                    }
                    onClicked: root.activateResult(index)
                    Keys.onReturnPressed: root.activateResult(index)
                    Keys.onEnterPressed: root.activateResult(index)
                    Keys.onDownPressed: { search.forceActiveFocus(); root.moveSelection(1); }
                    Keys.onUpPressed: { search.forceActiveFocus(); root.moveSelection(-1); }
                }
                ScrollBar.vertical: ScrollBar {}
            }
            Label {
                visible: !root.catalogReady || !root.matches.length
                text: !root.catalogReady ? "Loading applications…" : !search.text.trim() ? "Type an application or space name." : "No matches."
                color: Theme.muted; Layout.fillWidth: true
            }
        }
    }
}
