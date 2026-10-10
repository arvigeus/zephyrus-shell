import QtQuick
import Quickshell
import "../core"
import "../widgets"

// Quickshell only serves QML from directories its scanner reaches through
// imports, so every module directory is imported here even though entry points
// are loaded by URL from the Modules registry.
import "../modules/apps" as Apps
import "../modules/books" as Books
import "../modules/files" as Files
import "../modules/games" as Games
import "../modules/movies" as Movies
import "../modules/music" as Music
import "../modules/pictures" as Pictures
import "../modules/projects" as Projects
import "../modules/radio" as Radio
import "../modules/series" as Series
import "../modules/terminal" as Terminal

Item {
    id: root
    property bool readyToLoad: true
    property var currentModule: null
    property string currentModuleId: ""
    property bool currentLoadFailed: false
    Keys.onEscapePressed: event => {
        if (ShellState.panel === "module") { ShellState.showDesktop(); event.accepted = true; }
    }
    readonly property var entry: Modules.find(ShellState.moduleId)
    readonly property url backgroundImage: currentModule && currentModule.backgroundImage !== undefined ? currentModule.backgroundImage : ""
    readonly property real backgroundImageOpacity: currentModule && currentModule.backgroundImageOpacity !== undefined
        ? Math.max(0, Math.min(1, Number(currentModule.backgroundImageOpacity))) : 1
    readonly property int backgroundImageWidth: currentModule && currentModule.backgroundImageWidth !== undefined
        ? Math.max(1, Number(currentModule.backgroundImageWidth)) : 2560
    function syncCurrentModule() {
        let item = null;
        let failed = !root.entry && !!ShellState.moduleId;
        for (let index = 0; index < retainedModules.count; ++index) {
            const holder = retainedModules.itemAt(index);
            if (holder && holder.moduleId === ShellState.moduleId) {
                item = holder.contentItem;
                failed = failed || holder.loadStatus === Loader.Error;
                break;
            }
        }
        currentModule = item;
        currentModuleId = item ? ShellState.moduleId : "";
        currentLoadFailed = failed;
        if (item && ShellState.pendingModuleOpen) Qt.callLater(root.deliverModuleOpen);
        if (ShellState.panel === "module" && item) Qt.callLater(root.restoreModuleFocus);
    }
    function deliverModuleOpen() {
        const request = ShellState.pendingModuleOpen;
        if (!request || !currentModule || ShellState.panel !== "module" ||
                request.id !== ShellState.moduleId || request.id !== currentModuleId) return;
        ShellState.pendingModuleOpen = null;
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
                Qt.callLater(root.deliverModuleOpen);
                Qt.callLater(root.restoreModuleFocus);
            }
        }
        function onPendingModuleOpenChanged() { Qt.callLater(root.deliverModuleOpen); }
        function onModuleIdChanged() { Qt.callLater(root.syncCurrentModule); }
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
        visible: !!ShellState.moduleId && !root.currentModule && !root.currentLoadFailed
        BusySpinner { anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible }
        Label { text: "Loading " + (root.entry ? root.entry.name : "space") + "…"; color: Theme.muted }
    }

    // One loader per running module. Hidden modules keep their instance,
    // workers and playback until ShellState.stopModule() removes the entry.
    Repeater {
        id: retainedModules
        model: ScriptModel { values: ShellState.runningModuleIds }
        delegate: Item {
            id: retained
            required property string modelData
            readonly property string moduleId: modelData
            readonly property var contentItem: retainedLoader.item
            readonly property int loadStatus: retainedLoader.status
            objectName: "retained-" + moduleId
            anchors.fill: parent
            Component {
                id: hostFactory
                QtObject {
                    function close() { ShellState.stopModule(retained.moduleId); }
                    function hide() {
                        if (ShellState.moduleId === retained.moduleId) ShellState.showDesktop();
                    }
                    function openModule(moduleId, payload) {
                        if (!Modules.find(moduleId)) return false;
                        ShellState.openModule(moduleId, payload);
                        return true;
                    }
                }
            }
            Loader {
                id: retainedLoader
                objectName: ShellState.moduleId === retained.moduleId ? "moduleContent" : "inactiveModuleContent"
                property bool loadedOnce: false
                anchors.fill: parent
                anchors.margins: Theme.moduleMargin
                anchors.topMargin: Theme.moduleTopMargin
                // Creation waits for drawers to finish closing; once loaded, it stays.
                active: root.readyToLoad || loadedOnce
                asynchronous: true
                visible: status === Loader.Ready && ShellState.moduleId === retained.moduleId
                enabled: visible && ShellState.panel === "module"
                source: Modules.find(retained.moduleId) ? Qt.resolvedUrl("../modules/" + retained.moduleId + "/Main.qml") : ""
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
        visible: !!ShellState.moduleId && root.currentLoadFailed
        text: "This space could not load. Close it using the X in Spaces and try again."
        color: Theme.danger
        width: Math.min(500, parent.width - 56); wrapMode: Text.Wrap
    }
}
