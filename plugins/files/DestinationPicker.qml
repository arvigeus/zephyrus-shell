import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../widgets"

Dialog {
    id: root
    required property var service
    property string sourceProvider: "local"
    property var sourceEntry: ({})
    property string destinationProvider: "local"
    property string currentPath: ""
    property var folders: []
    property var crumbs: []
    property var initialLocations: ({})
    property bool showHidden: false
    readonly property var visibleFolders: folders.filter(e => showHidden || !e.hidden)
    property bool loading: false
    property bool locationReady: false
    property bool moveSource: false
    property string cursor: ""
    property string failure: ""
    property int generation: 0
    signal chosen(string provider, string path, bool moveSource)
    title: (moveSource ? "Move " : "Copy ") + (sourceEntry.name || "item")
    width: Math.min(620, parent.width - 24)
    height: Math.min(580, parent.height - 24)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    popupType: Popup.Item
    onClosed: { generation++; }

    function begin(source, record, destination, locations, move) {
        sourceProvider = source;
        sourceEntry = record;
        initialLocations = locations;
        destinationProvider = destination;
        moveSource = !!move;
        selectProvider(destination);
        open();
    }
    function selectProvider(provider) {
        destinationProvider = provider;
        const saved = initialLocations[provider];
        crumbs = saved && saved.crumbs ? saved.crumbs : [{label: provider === "local" ? "Home" : provider === "nextcloud" ? "Nextcloud" : "My Drive", path: provider === "local" ? service.homePath : provider === "nextcloud" ? "/" : "root"}];
        currentPath = saved && saved.path ? saved.path : crumbs[0].path;
        folders = [];
        cursor = "";
        load(currentPath, false);
    }
    function load(path, more) {
        const token = ++generation;
        loading = true;
        failure = "";
        if (!more) locationReady = false;
        service.request("list", {provider: destinationProvider, path: path, cursor: more ? cursor : "", context: "destination"}, (result, error) => {
            if (token !== generation) return;
            loading = false;
            if (error) { failure = error; return; }
            currentPath = result.path;
            locationReady = true;
            folders = (more ? folders : []).concat(result.entries.filter(e => e.is_dir));
            cursor = result.cursor || "";
        });
    }
    function enter(entry) {
        crumbs = crumbs.concat([{label: entry.name, path: entry.target_path || entry.path}]);
        load(entry.target_path || entry.path, false);
    }
    function up() {
        if (destinationProvider === "local" || destinationProvider === "nextcloud") {
            const home = destinationProvider === "local" ? service.homePath : "/";
            if (currentPath !== home) load(currentPath.substring(0, currentPath.lastIndexOf("/")) || home, false);
        } else if (crumbs.length > 1) {
            crumbs = crumbs.slice(0, -1);
            load(crumbs[crumbs.length - 1].path, false);
        }
    }
    background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: [{id:"local", name:"Local"}, {id:"nextcloud", name:"Nextcloud"}, {id:"gdrive", name:"Google Drive"}]
                delegate: Action {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name
                    iconArtwork: modelData.id === "nextcloud" ? Qt.resolvedUrl("../../assets/brands/nextcloud.svg") : ""
                    highlighted: root.destinationProvider === modelData.id
                    onClicked: root.selectProvider(modelData.id)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            IconButton { iconName: "house"; text: "Root folder"; onClicked: { root.crumbs = root.crumbs.slice(0, 1); root.load(root.crumbs[0].path, false); } }
            IconButton { iconName: "arrow-up"; text: "Parent folder"; onClicked: root.up() }
            IconButton { visible: root.destinationProvider === "local"; iconName: root.showHidden ? "eye-off" : "eye"; text: root.showHidden ? "Hide hidden folders" : "Show hidden folders"; onClicked: root.showHidden = !root.showHidden }
            Label { Layout.fillWidth: true; text: root.destinationProvider === "gdrive" ? root.crumbs.map(c => c.label).join(" / ") : root.currentPath; elide: Text.ElideMiddle; color: Theme.muted }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                id: folderList
                anchors.fill: parent
                clip: true
                visible: !root.failure
                model: root.visibleFolders
                currentIndex: -1
                ScrollBar.vertical: ScrollBar {}
                WheelScroll { view: folderList }
                delegate: ItemDelegate {
                    id: folderRow
                    required property var modelData
                    width: ListView.view.width
                    height: 42
                    contentItem: RowLayout {
                        Icon { name: "folder"; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                        Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                        Icon { name: "chevron-right"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                    }
                    background: Rectangle { color: folderRow.hovered || folderRow.highlighted ? Theme.raised : "transparent"; radius: Theme.controlRadius }
                    onClicked: root.enter(modelData)
                }
            }
            BusySpinner { anchors.centerIn: parent; running: root.loading; visible: running }
            Label {
                anchors.centerIn: parent
                width: parent.width - 16
                visible: !root.loading && (!!root.failure || !root.visibleFolders.length)
                text: root.failure || "No subfolders. You can use this folder."
                color: root.failure ? Theme.danger : Theme.muted
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
        Action { visible: !!root.cursor; enabled: !root.loading; text: "More folders"; onClicked: root.load(root.currentPath, true) }
        Label { Layout.fillWidth: true; text: root.moveSource ? "The source is moved to Trash only after the copy succeeds." : "Existing items are kept; copies receive a new name."; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.sp(12) }
    }
    footer: RowLayout {
        Item { Layout.fillWidth: true }
        Action { text: "Cancel"; onClicked: root.close() }
        Action { visible: !!root.failure; text: "Retry"; onClicked: root.load(root.currentPath || root.crumbs[0].path, false) }
        Action {
            text: root.moveSource ? "Move here" : "Copy here"
            highlighted: true
            enabled: root.locationReady && !root.loading && !root.failure
            onClicked: { root.chosen(root.destinationProvider, root.currentPath, root.moveSource); root.close(); }
        }
    }
}
