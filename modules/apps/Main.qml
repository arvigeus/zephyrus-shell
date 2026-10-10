import QtQuick
import QtQuick.Controls
import QtCore
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import "../../core"
import "../../widgets"
import "../../services"

ColumnLayout {
    id: root
    property var host
    property string category: ""
    property bool catalogReady: false
    property var favoriteIds: []
    property var gpuChoices: []
    property bool gpuChoicesReady: false
    property string launchError: ""
    property bool launching: false
    Worker {
        id: gpuWorker
        backend: "modules/apps/backend.py"
        serviceName: "Applications"
        onReady: request("gpus", {}, (result, error) => {
            root.gpuChoices = result ? result.gpus : [];
            root.gpuChoicesReady = true;
        })
    }
    Settings {
        id: preferences
        location: "file://" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/zephyrus-shell/applications.ini"
    }
    function isFavorite(id) { return favoriteIds.includes(id); }
    function toggleFavorite(id) {
        favoriteIds = isFavorite(id) ? favoriteIds.filter(value => value !== id) : favoriteIds.concat([id]);
        preferences.setValue("favorites", JSON.stringify(favoriteIds));
        preferences.sync();
    }
    Component.onCompleted: {
        try {
            const saved = JSON.parse(preferences.value("favorites", "[]"));
            favoriteIds = Array.isArray(saved) ? saved.filter(id => typeof id === "string") : [];
        } catch (error) { favoriteIds = []; }
        // DesktopEntry metadata arrives in a batch. Publish after it completes.
        Qt.callLater(root.refreshCatalogue);
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { Qt.callLater(root.refreshCatalogue); }
    }
    readonly property var categoryNames: ({AudioVideo: "Media", Development: "Development", Education: "Education", Game: "Games", Graphics: "Graphics", Network: "Internet", Office: "Office", Science: "Science", Settings: "Settings", System: "System", Utility: "Utilities"})
    property var catalogueEntries: DesktopEntries.applications.values
    readonly property var applications: publishedApplications
    property var publishedApplications: []
    onCatalogueEntriesChanged: Qt.callLater(root.refreshCatalogue)
    Instantiator {
        // Preserve observers as the scan inserts entries instead of resetting
        // the whole delegate model for each new membership snapshot.
        model: ScriptModel { values: root.catalogueEntries }
        delegate: Connections {
            required property var modelData
            target: modelData
            function onNameChanged() { Qt.callLater(root.refreshCatalogue); }
            function onNoDisplayChanged() { Qt.callLater(root.refreshCatalogue); }
        }
    }
    function refreshCatalogue() {
        const next = catalogueEntries.filter(app => !app.noDisplay).sort((a, b) => a.name.localeCompare(b.name));
        if (next.length !== publishedApplications.length
                || !next.every((app, index) => app === publishedApplications[index])) publishedApplications = next;
        if (!catalogReady) {
            category = next.some(app => isFavorite(app.id)) ? "favorites" : "";
            catalogReady = true;
        }
    }
    readonly property var categories: Object.keys(categoryNames).filter(key => applications.some(app => (app.categories || []).includes(key)))
    readonly property var searchIndex: applications.map(app => ({entry: app,
        terms: (app.name + " " + (app.genericName || "") + " " + (app.keywords || []).join(" ")).toLowerCase()}))
    readonly property var matches: publishedMatches
    property var publishedMatches: []
    readonly property var pendingMatches: {
        const query = search.text.trim().toLowerCase();
        const selectedCategory = category;
        const favorites = favoriteIds;
        return searchIndex.filter(item => {
            const app = item.entry;
            return (!selectedCategory || (selectedCategory === "favorites"
                ? (!!query || favorites.includes(app.id)) : (app.categories || []).includes(selectedCategory)))
                && item.terms.includes(query);
        }).map(item => item.entry);
    }
    onPendingMatchesChanged: {
        const next = pendingMatches;
        // A new query can have the same results. Keep the grid's model in that
        // case so it doesn't destroy and recreate all visible controls/artwork.
        if (next.length === publishedMatches.length
                && next.every((app, index) => app === publishedMatches[index])) return;
        publishedMatches = next;
    }
    function activate() { search.forceActiveFocus(); }
    function launch(app) { app.execute(); if (host) host.hide(); }
    function launchOnGpu(app, gpu) {
        if (launching) return;
        launching = true; launchError = "";
        gpuWorker.request("launch", {gpu: gpu.id, command: app.command, directory: app.workingDirectory, terminal: app.runInTerminal}, (result, error) => {
            root.launching = false;
            root.launchError = error;
            if (result && result.ok && root.host) root.host.hide();
        });
    }
    spacing: 16
    SearchField {
        id: search
        objectName: "appsSearchField"
        Layout.fillWidth: true
        placeholderText: "Search applications…"
        onTextChanged: apps.currentIndex = -1
        onAccepted: { if (root.matches.length) root.launch(root.matches[0]); }
        Keys.onDownPressed: { if (root.matches.length) { apps.forceActiveFocus(); apps.currentIndex = 0; } }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Action { text: "Favorites"; iconName: "star"; highlighted: root.category === "favorites"; onClicked: root.category = "favorites" }
        Action { text: "All applications"; highlighted: !root.category; onClicked: root.category = "" }
        Repeater {
            model: root.categories
            Action {
                required property string modelData
                text: root.categoryNames[modelData]
                highlighted: root.category === modelData
                onClicked: root.category = modelData
            }
        }
    }
    Label { visible: root.catalogReady; text: root.matches.length + (root.matches.length === 1 ? " application" : " applications"); color: Theme.muted }
    Label { visible: !!root.launchError; text: root.launchError; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    GridView {
        id: apps
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 150))
        cellHeight: 132
        model: root.catalogReady ? root.matches : []
        keyNavigationEnabled: true
        onModelChanged: currentIndex = -1
        WheelScroll { view: apps; pixelsPerNotch: Math.max(320, apps.cellHeight * 2) }
        delegate: Action {
            id: appButton
            required property var modelData
            required property int index
            property var launchMenu: null
            function toggleLaunchMenu() {
                if (!launchMenu) launchMenu = menuFactory.createObject(appButton);
                if (launchMenu.visible) launchMenu.close();
                else launchMenu.open();
            }
            width: GridView.view.cellWidth - 8; height: GridView.view.cellHeight - 8
            text: modelData.name
            highlighted: apps.activeFocus && apps.currentIndex === index
            contentItem: Item {
                AppIcon { icon: appButton.modelData.icon; anchors.horizontalCenter: parent.horizontalCenter; y: 4; width: 48; height: 48 }
                Text {
                    text: appButton.modelData.name
                    color: appButton.highlighted ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: Theme.sp(14)
                    x: 0; y: 62; width: parent.width; height: parent.height - y
                    verticalAlignment: Text.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            IconButton {
                id: favoriteButton
                anchors.top: parent.top; anchors.right: parent.right
                width: 32; height: 32; implicitWidth: 32; implicitHeight: 32
                iconName: root.isFavorite(appButton.modelData.id) ? "star-filled" : "star"
                iconSize: 18
                opacity: root.isFavorite(appButton.modelData.id) || appButton.hovered || hovered || activeFocus || appButton.activeFocus ? 1 : 0
                text: (root.isFavorite(appButton.modelData.id) ? "Remove " : "Add ") + appButton.modelData.name + (root.isFavorite(appButton.modelData.id) ? " from favorites" : " to favorites")
                onClicked: root.toggleFavorite(appButton.modelData.id)
            }
            IconButton {
                anchors.top: parent.top; anchors.left: parent.left
                objectName: "app-gpu-picker-" + appButton.index
                readonly property bool menuOpen: !!appButton.launchMenu && appButton.launchMenu.visible
                width: 32; height: 32; implicitWidth: 32; implicitHeight: 32
                visible: root.gpuChoices.length > 1
                opacity: appButton.hovered || hovered || activeFocus || appButton.activeFocus || menuOpen ? 1 : 0
                iconName: "gpu"; iconSize: 18
                text: "Choose GPU for " + appButton.modelData.name
                onClicked: appButton.toggleLaunchMenu()
            }
            onClicked: root.launch(modelData)
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: appButton.toggleLaunchMenu()
            }
            Keys.onMenuPressed: appButton.toggleLaunchMenu()
            // Most tiles never open this popup. Keep it owned by the tile, but
            // instantiate the controls only on the first actual interaction.
            Component {
                id: menuFactory
                Menu {
                    parent: appButton
                    popupType: Popup.Item
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    MenuItem { text: "Launch normally"; enabled: !root.launching; onTriggered: root.launch(appButton.modelData) }
                    Repeater {
                        model: root.gpuChoices.length > 1 ? root.gpuChoices : []
                        MenuItem {
                            required property var modelData
                            text: "Launch on " + modelData.name
                            enabled: !root.launching
                            onTriggered: root.launchOnGpu(appButton.modelData, modelData)
                        }
                    }
                }
            }
        }
        Keys.onReturnPressed: { if (currentItem) root.launch(currentItem.modelData); }
        Keys.onEnterPressed: { if (currentItem) root.launch(currentItem.modelData); }
        ScrollBar.vertical: ScrollBar {}
        Label {
            anchors.centerIn: parent
            visible: !root.catalogReady || !root.matches.length
            width: Math.min(500, parent.width - 32)
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: !root.catalogReady ? "Loading applications…" : root.category === "favorites" && !search.text.trim() ? "No favorites yet. Open All applications and use the star on an app to add it here." : !root.applications.length ? "No applications installed." : "No matching applications."
            color: Theme.muted
        }
    }
}
