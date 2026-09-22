import QtQuick
import QtQuick.Controls
import QtCore
import QtQuick.Layouts
import Quickshell
import "../../core"
import "../../widgets"

ColumnLayout {
    id: root
    property var host
    property string category: ""
    property bool catalogReady: false
    property var favoriteIds: []
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
        // The initial desktop scan delivers its results through a queued event.
        Qt.callLater(() => {
            root.category = root.applications.some(app => root.isFavorite(app.id)) ? "favorites" : "";
            root.catalogReady = true;
        });
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.catalogReady = true; }
    }
    readonly property var categoryNames: ({AudioVideo: "Media", Development: "Development", Education: "Education", Game: "Games", Graphics: "Graphics", Network: "Internet", Office: "Office", Science: "Science", Settings: "Settings", System: "System", Utility: "Utilities"})
    readonly property var applications: DesktopEntries.applications.values.filter(app => !app.noDisplay).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var categories: Object.keys(categoryNames).filter(key => applications.some(app => (app.categories || []).includes(key)))
    readonly property var matches: applications.filter(app => (!category || (category === "favorites" ? (search.text.trim() ? true : isFavorite(app.id)) : (app.categories || []).includes(category))) && (app.name + " " + app.genericName + " " + (app.keywords || []).join(" ")).toLowerCase().includes(search.text.trim().toLowerCase()))
    function activate() { search.forceActiveFocus(); }
    function launch(app) { app.execute(); if (host) host.close(); }
    spacing: 16
    SearchField {
        id: search
        Layout.fillWidth: true
        placeholderText: "Search applications…"
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
            width: GridView.view.cellWidth - 8; height: GridView.view.cellHeight - 8
            text: modelData.name
            highlighted: apps.activeFocus && apps.currentIndex === index
            contentItem: Item {
                AppIcon { icon: appButton.modelData.icon; anchors.horizontalCenter: parent.horizontalCenter; y: 4; width: 48; height: 48 }
                Text {
                    text: appButton.modelData.name
                    color: appButton.highlighted ? Theme.accent : Theme.text
                    font.pixelSize: 14
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
            onClicked: root.launch(modelData)
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
