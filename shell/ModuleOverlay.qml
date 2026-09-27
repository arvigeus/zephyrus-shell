import QtQuick
import QtQuick.Controls
import "../core"
import "../widgets"

Item {
    id: root
    property bool readyToLoad: true
    property string screenName: ""
    property var currentModule: null
    property bool currentLoadFailed: false
    readonly property var entry: Plugins.find(ShellState.pluginId)
    // Modules may tune backdrop opacity and decode width; defaults preserve prior behavior.
    readonly property url backgroundImage: currentModule && currentModule.backgroundImage !== undefined ? currentModule.backgroundImage : ""
    readonly property real backgroundImageOpacity: currentModule && currentModule.backgroundImageOpacity !== undefined
        ? Math.max(0, Math.min(1, Number(currentModule.backgroundImageOpacity))) : 1
    readonly property int backgroundImageWidth: currentModule && currentModule.backgroundImageWidth !== undefined
        ? Math.max(1, Number(currentModule.backgroundImageWidth)) : 2560
    function syncRetainedRegistry() {
        const wanted = Plugins.entries.map(value => value.id);
        for (let index = retainedRegistry.count - 1; index >= 0; --index)
            if (!wanted.includes(retainedRegistry.get(index).pluginId)) retainedRegistry.remove(index);
        for (const id of wanted) {
            let found = false;
            for (let index = 0; index < retainedRegistry.count; ++index)
                if (retainedRegistry.get(index).pluginId === id) { found = true; break; }
            if (!found) retainedRegistry.append({pluginId: id});
        }
        Qt.callLater(root.syncCurrentModule);
    }
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
        currentLoadFailed = failed;
        if (ShellState.panel === "module" && item) Qt.callLater(root.restoreModuleFocus);
    }
    function restoreModuleFocus() {
        if (ShellState.panel !== "module" || !currentModule) return;
        root.forceActiveFocus();
        if (typeof currentModule.activate === "function") currentModule.activate();
    }

    Connections {
        target: ShellState
        function onPanelChanged() {
            if (ShellState.panel === "module") Qt.callLater(root.restoreModuleFocus);
        }
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
    Connections {
        target: Plugins
        function onEntriesChanged() { root.syncRetainedRegistry(); }
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
    Shortcut { sequence: "Escape"; enabled: ShellState.panel === "module"; onActivated: ShellState.close() }
    Component.onCompleted: {
        forceActiveFocus();
        syncRetainedRegistry();
    }
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !!ShellState.pluginId && !root.currentModule && !root.currentLoadFailed
        BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: parent.visible }
        Label { text: "Loading " + (root.entry ? root.entry.name : "space") + "…"; color: Theme.muted }
    }
    ListModel { id: retainedRegistry }
    Repeater {
        id: retainedModules
        model: retainedRegistry
        delegate: Item {
            id: retained
            required property string pluginId
            readonly property var contentItem: retainedLoader.item
            readonly property int loadStatus: retainedLoader.status
            objectName: "retained-" + pluginId
            anchors.fill: parent
            Loader {
                id: retainedLoader
                objectName: ShellState.pluginId === retained.pluginId ? "moduleContent" : "inactiveModuleContent"
                property bool loadedOnce: false
                anchors.fill: parent
                anchors.margins: Theme.moduleMargin
                anchors.topMargin: Theme.moduleTopMargin
                active: ShellState.runningPluginIds.includes(retained.pluginId)
                    && ShellState.runningPluginMonitors[retained.pluginId] === root.screenName
                    && (root.readyToLoad || loadedOnce)
                asynchronous: true
                visible: status === Loader.Ready && ShellState.pluginId === retained.pluginId
                source: {
                    const retainedEntry = Plugins.find(retained.pluginId);
                    return retainedEntry ? retainedEntry.entry : "";
                }
                onActiveChanged: if (!active) loadedOnce = false
                onLoaded: {
                    loadedOnce = true;
                    item.host = host;
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
        text: "This space could not load. Close it with Escape, then reload spaces."
        color: Theme.danger
        width: Math.min(500, parent.width - 56); wrapMode: Text.Wrap
    }
    QtObject {
        id: host
        readonly property int apiVersion: 1
        function close() { ShellState.close(); }
        function back() { ShellState.backToSpaces(); }
        function requestKeepRunning(pluginId, enabled) { ShellState.requestKeepRunning(pluginId, enabled); }
    }
}
