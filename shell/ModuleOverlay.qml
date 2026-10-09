import QtQuick
import QtQuick.Controls
import Quickshell
import "../core"
import "../widgets"

import "../plugins/apps" as Apps
import "../plugins/files" as Files
import "../plugins/terminal" as Terminal
import "../plugins/projects" as Projects
import "../plugins/movies" as Movies
import "../plugins/series" as Series
import "../plugins/music" as Music
import "../plugins/radio" as Radio
import "../plugins/pictures" as Pictures
import "../plugins/games" as Games
import "../plugins/books" as Books

Item {
    id: root
    property bool readyToLoad: true
    property string screenName: ""
    property var currentModule: null
    property string currentModuleId: ""
    property bool currentLoadFailed: false
    Keys.onEscapePressed: event => {
        if (ShellState.panel === "module") { ShellState.close(); event.accepted = true; }
    }
    readonly property var entry: Modules.find(ShellState.pluginId)
    // Modules may tune backdrop opacity and decode width; defaults preserve prior behavior.
    readonly property url backgroundImage: currentModule && currentModule.backgroundImage !== undefined ? currentModule.backgroundImage : ""
    readonly property real backgroundImageOpacity: currentModule && currentModule.backgroundImageOpacity !== undefined
        ? Math.max(0, Math.min(1, Number(currentModule.backgroundImageOpacity))) : 1
    readonly property int backgroundImageWidth: currentModule && currentModule.backgroundImageWidth !== undefined
        ? Math.max(1, Number(currentModule.backgroundImageWidth)) : 2560
    function syncCurrentModule() {
        let item = null;
        let failed = !root.entry && !!ShellState.pluginId;
        if (ShellState.pluginId && ShellState.runningPluginIds.includes(ShellState.pluginId)) {
            for (let index = 0; index < retainedModules.count; ++index) {
                const holder = retainedModules.itemAt(index);
                if (holder && holder.pluginId === ShellState.pluginId) {
                    item = holder.contentItem;
                    failed = holder.loadStatus === Loader.Error;
                    break;
                }
            }
        }
        currentModule = item;
        currentModuleId = item ? ShellState.pluginId : "";
        currentLoadFailed = failed;
        if (item && ShellState.pendingPluginOpen) Qt.callLater(root.deliverPluginOpen);
        if (ShellState.panel === "module" && item) Qt.callLater(root.restoreModuleFocus);
    }
    function deliverPluginOpen() {
        const request = ShellState.pendingPluginOpen;
        if (!request || !currentModule || ShellState.panel !== "module" ||
                request.id !== ShellState.pluginId || request.id !== currentModuleId) return;
        ShellState.pendingPluginOpen = null;
        if (typeof currentModule.handleOpen === "function") currentModule.handleOpen(request.payload);
    }
    function restoreModuleFocus() {
        if (ShellState.panel !== "module" || !currentModule) return;
        root.forceActiveFocus();
        if (typeof currentModule.activate === "function") currentModule.activate();
    }

    Connections {
        target: ShellState
        function onPanelChanged() {
            if (ShellState.panel === "module") {
                Qt.callLater(root.deliverPluginOpen);
                Qt.callLater(root.restoreModuleFocus);
            }
        }
        function onPendingPluginOpenChanged() { Qt.callLater(root.deliverPluginOpen); }
        function onPluginIdChanged() {
            Qt.callLater(root.syncCurrentModule);
        }
        function onMonitorChanged() {
            Qt.callLater(root.syncCurrentModule);
        }
        function onPluginMonitorChanged() {
            Qt.callLater(root.syncCurrentModule);
        }
    }
    Rectangle {
        anchors.fill: parent
        color: root.backgroundImage.toString() ? Theme.background : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.88)
    }
    CrossfadeImage {
        anchors.fill: parent
        source: root.backgroundImage
        imageWidth: root.backgroundImageWidth
        opacity: root.backgroundImageOpacity
    }
    Component.onCompleted: {
        forceActiveFocus();
        Qt.callLater(root.syncCurrentModule);
    }
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !!ShellState.pluginId && !root.currentModule && !root.currentLoadFailed
        BusySpinner { anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible }
        Label { text: "Loading " + (root.entry ? root.entry.name : "space") + "…"; color: Theme.muted }
    }
    // Components are compiled with the shell; instances and workers remain lazy.
    readonly property var components: ({
        apps: appsComponent,
        files: filesComponent,
        terminal: terminalComponent,
        projects: projectsComponent,
        movies: moviesComponent,
        series: seriesComponent,
        music: musicComponent,
        radio: radioComponent,
        pictures: picturesComponent,
        games: gamesComponent,
        books: booksComponent
    })
    Component { id: appsComponent; Apps.Main {} }
    Component { id: filesComponent; Files.Main {} }
    Component { id: terminalComponent; Terminal.Main {} }
    Component { id: projectsComponent; Projects.Main {} }
    Component { id: moviesComponent; Movies.Main {} }
    Component { id: seriesComponent; Series.Main {} }
    Component { id: musicComponent; Music.Main {} }
    Component { id: radioComponent; Radio.Main {} }
    Component { id: picturesComponent; Pictures.Main {} }
    Component { id: gamesComponent; Games.Main {} }
    Component { id: booksComponent; Books.Main {} }

    Repeater {
        id: retainedModules
        model: ScriptModel {
            values: ShellState.runningPluginIds
        }
        delegate: Item {
            id: retained
            required property string modelData
            readonly property string pluginId: modelData
            readonly property var contentItem: retainedLoader.item
            readonly property int loadStatus: retainedLoader.status
            objectName: "retained-" + pluginId
            anchors.fill: parent
            // Each live module gets a host scoped to its own lifetime, including while hidden.
            Component {
                id: hostFactory
                QtObject {
                    readonly property int apiVersion: 2
                    function close() { ShellState.stopPlugin(retained.pluginId); }
                    function hide() {
                        if (ShellState.pluginId === retained.pluginId) ShellState.showDesktop();
                    }
                    function back() {
                        if (ShellState.pluginId === retained.pluginId) ShellState.backToSpaces();
                    }
                    function openPlugin(pluginId, payload) {
                        if (!Modules.find(pluginId)) return false;
                        ShellState.openPlugin(pluginId, payload);
                        return true;
                    }
                }
            }
            Loader {
                id: retainedLoader
                objectName: ShellState.pluginId === retained.pluginId ? "moduleContent" : "inactiveModuleContent"
                property bool loadedOnce: false
                anchors.fill: parent
                anchors.margins: Theme.moduleMargin
                anchors.topMargin: Theme.moduleTopMargin
                active: ShellState.runningPluginIds.includes(retained.pluginId)
                    && (root.screenName === "*" || ShellState.runningPluginMonitors[retained.pluginId] === root.screenName)
                    && (root.readyToLoad || loadedOnce)
                asynchronous: true
                visible: status === Loader.Ready && ShellState.pluginId === retained.pluginId
                enabled: visible && ShellState.panel === "module"
                sourceComponent: root.components[retained.pluginId] || null
                onActiveChanged: if (!active) loadedOnce = false
                onLoaded: {
                    loadedOnce = true;
                    item.host = hostFactory.createObject(item);
                    root.syncCurrentModule();
                }
                onStatusChanged: Qt.callLater(root.syncCurrentModule)
            }
        }
        onItemAdded: Qt.callLater(root.syncCurrentModule)
        onItemRemoved: Qt.callLater(root.syncCurrentModule)
    }
    Label {
        anchors.centerIn: parent
        visible: !!ShellState.pluginId && root.currentLoadFailed
        text: "This space could not load. Close it using the X in Spaces and try again."
        color: Theme.danger
        width: Math.min(500, parent.width - 56); wrapMode: Text.Wrap
    }
}
