import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../widgets"

ColumnLayout {
    id: root
    property var host
    property string currentPath: ""
    property var entries: []
    property string errorText: ""
    property string statusText: ""
    property string pendingDeletePath: ""
    property bool loading: true
    property bool showHidden: false
    property int browseGeneration: 0
    readonly property var visibleEntries: entries.filter(entry => (showHidden || !entry.hidden) && entry.name.toLowerCase().includes(search.text.trim().toLowerCase()))
    spacing: 12

    function breadcrumbs(path) {
        const parts = path === service.homePath ? [] : path.substring(service.homePath.length + 1).split("/");
        const result = [{label: "Home", path: service.homePath}];
        let accumulated = service.homePath;
        for (const part of parts) {
            accumulated += "/" + part;
            result.push({label: part, path: accumulated});
        }
        return result;
    }
    function iconFor(entry) {
        if (entry.is_dir) return "folder";
        const ext = entry.extension;
        if ([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".heic", ".tif", ".tiff"].includes(ext)) return "image";
        if ([".mp4", ".mkv", ".mov", ".avi", ".webm", ".mpeg", ".mpg", ".m4v", ".wmv"].includes(ext)) return "video";
        if ([".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus", ".wma"].includes(ext)) return "music";
        if ([".pdf", ".txt", ".md", ".doc", ".docx", ".odt", ".rtf", ".xls", ".xlsx", ".ods", ".ppt", ".pptx", ".csv"].includes(ext)) return "file-text";
        if ([".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".tgz"].includes(ext)) return "archive";
        return "file";
    }
    function copyPath(path) {
        service.request("copy", {path: path}, function(result, error) {
            statusText = error || (result ? result.message : "");
        });
    }
    function activate() { fileList.forceActiveFocus(); }

    function load(path) {
        const generation = ++browseGeneration;
        loading = true;
        errorText = "";
        service.request("list", {path: path || ""}, function(result, error) {
            if (generation !== browseGeneration) return;
            loading = false;
            if (error) { errorText = error; entries = []; return; }
            currentPath = result.path;
            entries = result.entries;
            fileList.currentIndex = root.visibleEntries.length ? 0 : -1;
            Qt.callLater(() => fileList.forceActiveFocus());
        });
    }
    function openEntry(entry) {
        statusText = "";
        if (entry.is_dir) load(entry.path);
        else service.request("open", {path: entry.path}, function(result, error) {
            statusText = error || "";
            if (!error && result && host) host.close();
        });
    }
    function runAction(op, entry) {
        statusText = "";
        service.request(op, {path: entry.path}, function(result, error) {
            statusText = error || (result ? result.message : "");
            if (!error && result && ["terminal", "reveal"].includes(op) && host) host.close();
        });
    }
    function openActions(button, menu, entryPath) {
        if (menu.visible) { menu.close(); return; }
        menu.parent = button;
        if (pendingDeletePath && pendingDeletePath !== entryPath) {
            pendingDeletePath = "";
            deleteConfirmation.stop();
        }
        const window = root.Window.window;
        const selectedIndex = pendingDeletePath === entryPath ? 4 : 0;
        if (!window) { menu.open(); menu.currentIndex = selectedIndex; return; }
        const point = button.mapToItem(window.contentItem, 0, 0);
        const menuX = Math.max(8, Math.min(point.x + button.width - menu.width, window.width - menu.width - 8));
        const menuHeight = menu.implicitHeight || 168;
        const below = point.y + button.height;
        const menuY = below + menuHeight <= window.height - 8 ? below : Math.max(8, point.y - menuHeight);
        menu.x = menuX - point.x;
        menu.y = menuY - point.y;
        menu.open();
        menu.currentIndex = selectedIndex;
    }
    function activateMenuAction(actionIndex, entry, menu) {
        if (actionIndex === 4 && pendingDeletePath !== entry.path) {
            root.confirmDelete(entry);
            Qt.callLater(() => {
                if (root.pendingDeletePath === entry.path && !menu.visible)
                    root.openActions(menu.anchorButton, menu, entry.path);
            });
            return;
        }
        menu.close();
        if (actionIndex === 0) root.openEntry(entry);
        else if (actionIndex === 1) root.runAction("terminal", entry);
        else if (actionIndex === 2) root.runAction("reveal", entry);
        else if (actionIndex === 3) root.copyPath(entry.path);
        else if (actionIndex === 4) root.confirmDelete(entry);
    }
    function confirmDelete(entry) {
        if (pendingDeletePath !== entry.path) {
            pendingDeletePath = entry.path;
            deleteConfirmation.restart();
            statusText = "";
            return;
        }
        deleteConfirmation.stop();
        pendingDeletePath = "";
        service.request("delete", {path: entry.path}, function(result, error) {
            statusText = error || (result ? "Moved " + entry.name + " to Trash" : "");
            if (!error && result) root.load(currentPath);
        });
    }
    function goUp() { if (currentPath !== service.homePath) load(currentPath.substring(0, currentPath.lastIndexOf("/")) || service.homePath); }
    function moveSelection(delta) {
        if (!visibleEntries.length) return;
        fileList.currentIndex = fileList.currentIndex < 0 ? 0 : Math.max(0, Math.min(visibleEntries.length - 1, fileList.currentIndex + delta));
        fileList.positionViewAtIndex(fileList.currentIndex, ListView.Contain);
    }
    Component.onCompleted: load("")

    Timer {
        id: deleteConfirmation
        interval: 10000
        repeat: false
        onTriggered: root.pendingDeletePath = ""
    }

    FilesService { id: service }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IconButton { iconName: "house"; text: "Go to home"; onClicked: root.load(service.homePath) }
        IconButton { iconName: "arrow-up"; text: "Go to parent folder"; enabled: root.currentPath !== service.homePath; onClicked: root.goUp() }
        Flickable {
            id: breadcrumbScroll
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            Layout.minimumHeight: 42
            Layout.maximumHeight: 42
            contentWidth: breadcrumbRow.width; contentHeight: height
            clip: true; flickableDirection: Flickable.HorizontalFlick
            Row {
                id: breadcrumbRow
                width: childrenRect.width
                height: breadcrumbScroll.height
                spacing: 2
                Repeater {
                    model: root.currentPath ? root.breadcrumbs(root.currentPath) : []
                    delegate: Row {
                        required property var modelData
                        required property int index
                        height: breadcrumbRow.height
                        spacing: 2
                        Action {
                            text: modelData.label
                            height: parent.height
                            implicitHeight: parent.height
                            flat: true
                            onClicked: root.load(modelData.path)
                            background: Rectangle {
                                radius: Theme.controlRadius
                                color: parent.down ? Theme.raised : parent.hovered ? Theme.surface : "transparent"
                            }
                        }
                        Icon { visible: index < root.breadcrumbs(root.currentPath).length - 1; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; name: "chevron-right" }
                    }
                }
            }
        }
        IconButton { iconName: root.showHidden ? "eye-off" : "eye"; text: root.showHidden ? "Hide hidden files" : "Show hidden files"; onClicked: root.showHidden = !root.showHidden }
        IconButton { iconName: "folder-open"; text: "Open this folder in the file manager"; enabled: !!root.currentPath; onClicked: root.runAction("reveal", {path: root.currentPath}) }
        IconButton { iconName: "copy"; text: "Copy current folder path"; enabled: !!root.currentPath; onClicked: root.copyPath(root.currentPath) }
        IconButton { iconName: "refresh-cw"; text: "Refresh"; onClicked: root.load(root.currentPath) }
    }
    RowLayout {
        Layout.fillWidth: true
        SearchField { id: search; Layout.fillWidth: true; placeholderText: "Search this folder…" }
        Label { text: root.visibleEntries.length + (root.visibleEntries.length === 1 ? " item" : " items"); color: Theme.muted }
    }
    Label { visible: !!root.statusText; text: root.statusText; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }

    ListView {
        id: fileList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.visibleEntries
        onModelChanged: currentIndex = root.visibleEntries.length ? 0 : -1
        spacing: 2
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            property alias actionButton: gear
            property alias actionMenu: actions
            readonly property bool selected: fileList.currentIndex === index && (fileList.activeFocus || gear.activeFocus)
            width: ListView.view.width
            height: 52
            Rectangle {
                anchors.fill: parent
                radius: Theme.controlRadius
                color: rowMouse.containsMouse ? Theme.surface : row.selected ? Theme.accentSurface : Theme.background
            }
            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; name: root.iconFor(row.modelData) }
            Label { x: 48; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 110; text: row.modelData.name; color: Theme.text; elide: Text.ElideRight }
            Label { anchors.right: gear.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.is_dir ? "Folder" : row.modelData.size_label; color: Theme.muted; font.pixelSize: 12 }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { fileList.currentIndex = index; fileList.forceActiveFocus(); root.openEntry(row.modelData); }
            }
            HoverHandler { id: rowHover }
            IconButton {
                id: gear
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; implicitWidth: 36; implicitHeight: 36
                iconName: "settings"; iconSize: 20; text: "Actions for " + row.modelData.name
                visible: rowHover.hovered || hovered || activeFocus
                ToolTip.visible: false
                onClicked: root.openActions(gear, actions, row.modelData.path)
                Keys.onLeftPressed: (event) => { root.goUp(); fileList.forceActiveFocus(); event.accepted = true; }
                Keys.onRightPressed: (event) => { root.openActions(gear, actions, row.modelData.path); event.accepted = true; }
                Keys.onSpacePressed: (event) => { root.openActions(gear, actions, row.modelData.path); event.accepted = true; }
                Keys.onUpPressed: { root.moveSelection(-1); fileList.forceActiveFocus(); }
                Keys.onDownPressed: { root.moveSelection(1); fileList.forceActiveFocus(); }
                Menu {
                    id: actions
                    property var anchorButton: gear
                    popupType: Popup.Item
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    width: 220
                    focus: true
                    background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
                    onClosed: fileList.forceActiveFocus()
                    MenuItem {
                        id: openAction
                        text: "Open"
                        implicitHeight: 42
                        leftPadding: 12; rightPadding: 12
                        contentItem: Label { text: openAction.text; color: openAction.highlighted ? Theme.accent : Theme.text; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: openAction.highlighted ? Theme.raised : "transparent" }
                        onTriggered: root.activateMenuAction(0, row.modelData, actions)
                        Keys.onReturnPressed: (event) => { root.activateMenuAction(0, row.modelData, actions); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { root.activateMenuAction(0, row.modelData, actions); event.accepted = true; }
                        Keys.onRightPressed: (event) => { root.activateMenuAction(0, row.modelData, actions); event.accepted = true; }
                        Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                        Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                    }
                    MenuItem {
                        id: terminalAction
                        text: "Open in terminal"
                        implicitHeight: 42
                        leftPadding: 12; rightPadding: 12
                        contentItem: Label { text: terminalAction.text; color: terminalAction.highlighted ? Theme.accent : Theme.text; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: terminalAction.highlighted ? Theme.raised : "transparent" }
                        onTriggered: root.activateMenuAction(1, row.modelData, actions)
                        Keys.onReturnPressed: (event) => { root.activateMenuAction(1, row.modelData, actions); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { root.activateMenuAction(1, row.modelData, actions); event.accepted = true; }
                        Keys.onRightPressed: (event) => { root.activateMenuAction(1, row.modelData, actions); event.accepted = true; }
                        Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                        Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                    }
                    MenuItem {
                        id: revealAction
                        text: "Show in file manager"
                        implicitHeight: 42
                        leftPadding: 12; rightPadding: 12
                        contentItem: Label { text: revealAction.text; color: revealAction.highlighted ? Theme.accent : Theme.text; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: revealAction.highlighted ? Theme.raised : "transparent" }
                        onTriggered: root.activateMenuAction(2, row.modelData, actions)
                        Keys.onReturnPressed: (event) => { root.activateMenuAction(2, row.modelData, actions); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { root.activateMenuAction(2, row.modelData, actions); event.accepted = true; }
                        Keys.onRightPressed: (event) => { root.activateMenuAction(2, row.modelData, actions); event.accepted = true; }
                        Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                        Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                    }
                    MenuItem {
                        id: copyAction
                        text: "Copy path"
                        implicitHeight: 42
                        leftPadding: 12; rightPadding: 12
                        contentItem: Label { text: copyAction.text; color: copyAction.highlighted ? Theme.accent : Theme.text; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: copyAction.highlighted ? Theme.raised : "transparent" }
                        onTriggered: root.activateMenuAction(3, row.modelData, actions)
                        Keys.onReturnPressed: (event) => { root.activateMenuAction(3, row.modelData, actions); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { root.activateMenuAction(3, row.modelData, actions); event.accepted = true; }
                        Keys.onRightPressed: (event) => { root.activateMenuAction(3, row.modelData, actions); event.accepted = true; }
                        Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                        Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                    }
                    MenuItem {
                        id: deleteAction
                        text: root.pendingDeletePath === row.modelData.path ? "You sure?" : "Move to Trash"
                        implicitHeight: 42
                        leftPadding: 12; rightPadding: 12
                        contentItem: RowLayout {
                            spacing: 8
                            Icon { name: "trash-2"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
                            Label { text: deleteAction.text; color: Theme.danger; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                        }
                        background: Rectangle { color: deleteAction.highlighted ? Theme.accentSurface : "transparent" }
                        onTriggered: root.activateMenuAction(4, row.modelData, actions)
                        Keys.onReturnPressed: (event) => { root.activateMenuAction(4, row.modelData, actions); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { root.activateMenuAction(4, row.modelData, actions); event.accepted = true; }
                        Keys.onRightPressed: (event) => { root.activateMenuAction(4, row.modelData, actions); event.accepted = true; }
                        Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                        Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                    }
                }
            }
        }
        ScrollBar.vertical: ScrollBar {}
        WheelScroll { view: fileList; pixelsPerNotch: 96 }
        focus: true
        Keys.onUpPressed: (event) => { root.moveSelection(-1); event.accepted = true; }
        Keys.onDownPressed: (event) => { root.moveSelection(1); event.accepted = true; }
        Keys.onReturnPressed: (event) => { if (currentItem && currentIndex >= 0) root.openEntry(currentItem.modelData); event.accepted = true; }
        Keys.onEnterPressed: (event) => { if (currentItem && currentIndex >= 0) root.openEntry(currentItem.modelData); event.accepted = true; }
        Keys.onRightPressed: (event) => { if (currentItem && currentIndex >= 0) root.openEntry(currentItem.modelData); event.accepted = true; }
        Keys.onLeftPressed: (event) => { root.goUp(); event.accepted = true; }
        Keys.onSpacePressed: (event) => { if (currentItem && currentIndex >= 0) root.openActions(currentItem.actionButton, currentItem.actionMenu, currentItem.modelData.path); event.accepted = true; }
        Label {
            anchors.centerIn: parent
            width: Math.min(500, parent.width - 32)
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            visible: root.loading || !!root.errorText || !root.visibleEntries.length
            text: root.loading ? "Loading files…" : root.errorText ? root.errorText : search.text.trim() ? "No matching files." : root.showHidden ? "This folder is empty." : "This folder is empty. Hidden files are not shown."
            color: root.errorText ? Theme.danger : Theme.muted
        }
    }
}
