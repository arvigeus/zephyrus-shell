import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../widgets"

ColumnLayout {
    id: root
    property alias fileWorker: service
    property alias transferPicker: destinationPicker
    property alias signInDialog: driveCallback
    property alias activityCenter: activity
    property var host
    property string providerName: "local"
    property var locations: ({})
    property var cloudCrumbs: []
    property string nextCursor: ""
    readonly property string rootPath: providerName === "local" ? service.homePath : providerName === "nextcloud" ? "/" : "root"
    readonly property int activeWorkCount: service.activeJobCount + service.activeEditCount + activeActionJobs.length + pendingActionStarts
    readonly property bool driveSignInActive: service.jobs.some(job => job.title === "Connect Google Drive" && ["queued", "running"].includes(job.state) && !job.cancel_requested)
    onHostChanged: updateActionRetention()
    onVisibleChanged: {
        if (!visible) {
            destinationPicker.close(); newFolder.close(); driveCallback.close(); activity.close();
            if (activeActionsMenu) activeActionsMenu.close();
        }
    }
    onActiveWorkCountChanged: updateActionRetention()
    property bool statusIsError: false
    onStatusTextChanged: { if (statusText) activity.notify(statusText, statusIsError); }
    function notifyStatus(message, error) { statusText = ""; statusIsError = !!error; statusText = message || ""; }

    function switchProvider(name) {
        if (activeActionsMenu) activeActionsMenu.close();
        locations = Object.assign({}, locations, {[providerName]: {path: currentPath, crumbs: breadcrumbs(currentPath)}});
        providerName = name;
        pendingDeletePath = "";
        search.text = "";
        entries = [];
        const saved = locations[name];
        cloudCrumbs = saved && saved.crumbs ? saved.crumbs : [{label: name === "nextcloud" ? "Nextcloud" : "My Drive", path: rootPath}];
        currentPath = saved && saved.path ? saved.path : rootPath;
        load(currentPath);
    }
    function chooseTransfer(entry, destination, move) {
        const saved = Object.assign({}, locations, {[providerName]: {path: currentPath, crumbs: breadcrumbs(currentPath)}});
        destinationPicker.begin(providerName, entry, destination || (providerName === "local" ? "nextcloud" : "local"), saved, move);
    }
    function jump(path) {
        if (providerName === "gdrive") {
            const index = cloudCrumbs.findIndex(c => c.path === path);
            if (index >= 0) cloudCrumbs = cloudCrumbs.slice(0, index + 1);
        }
        load(path);
    }
    function createFolder() { folderName.text = ""; newFolder.open(); }
    function connectDrive() {
        activity.open();
        service.connectDrive();
    }
    function retryFolder() {
        if (providerName === "gdrive" && driveNeedsSignIn) connectDrive();
        else load(currentPath);
    }
    function finishDriveSignIn() { activity.close(); driveCallback.open(); }
    function submitDriveCallback() {
        const url = callbackAddress.text.trim();
        if (!url || driveCallback.submitting) return;
        callbackAddress.clear();
        driveCallback.submitting = true;
        service.request("complete_drive_sign_in", {callback_url: url}, (result, error) => {
            driveCallback.submitting = false;
            activity.notify(error || result.message, !!error);
            if (!error) driveCallback.close();
        });
    }
    function handleOpen(payload) {
        if (!payload || !payload.path) return;
        if (providerName !== "local") switchProvider("local");
        load(payload.path);
    }
    property string currentPath: ""
    property var entries: []
    property string errorText: ""
    property bool driveNeedsSignIn: false
    readonly property string folderRetryText: driveNeedsSignIn
        ? (driveSignInActive ? "Continue Google sign-in" : "Connect Google Drive")
        : "Retry loading folder"
    property string statusText: ""
    property string pendingDeletePath: ""
    property bool loading: true
    property bool showHidden: false
    property int browseGeneration: 0
    property int actionMenuGeneration: 0
    property var activeActionsMenu: null
    property var activeActionJobs: []
    property var pollingActionJobs: ({})
    property int pendingActionStarts: 0
    readonly property var visibleEntries: entries.filter(entry => (showHidden || !entry.hidden) && entry.name.toLowerCase().includes(search.text.trim().toLowerCase()))
    spacing: 12

    function breadcrumbs(path) {
        if (providerName === "gdrive") return cloudCrumbs;
        if (providerName === "nextcloud") {
            let accumulated = "";
            return [{label: "Nextcloud", path: "/"}].concat((path || "").split("/").filter(Boolean).map(part => {
                accumulated += "/" + part;
                return {label: part, path: accumulated};
            }));
        }
        const parts = !path || path === service.homePath ? [] : path.substring(service.homePath.length + 1).split("/");
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
        if ([".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus", ".wma", ".mka"].includes(ext)) return "music";
        if ([".pdf", ".txt", ".md", ".doc", ".docx", ".odt", ".rtf", ".xls", ".xlsx", ".ods", ".ppt", ".pptx", ".csv"].includes(ext)) return "file-text";
        if ([".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".tgz"].includes(ext)) return "archive";
        return "file";
    }
    function copyPath(path) {
        service.request("copy", {path: path}, function(result, error) {
            notifyStatus(error || (result ? result.message : ""), !!error);
        });
    }
    function activate() { fileList.forceActiveFocus(); if (activeWorkCount) activity.open(); }

    function load(path, more) {
        const generation = ++browseGeneration;
        if (!more && path && path !== currentPath) entries = [];
        currentPath = path || rootPath;
        loading = true;
        errorText = "";
        driveNeedsSignIn = false;
        service.request("list", {provider: providerName, path: path || rootPath, cursor: more ? nextCursor : "", context: "browse"}, function(result, error, errorCode) {
            if (generation !== browseGeneration) return;
            loading = false;
            if (error) {
                driveNeedsSignIn = errorCode === "google_drive_sign_in_required";
                errorText = error;
                activity.notify(error, true);
                return;
            }
            currentPath = result.path;
            entries = (more ? entries : []).concat(result.entries);
            nextCursor = result.cursor || "";
            fileList.currentIndex = root.visibleEntries.length ? 0 : -1;
            Qt.callLater(() => fileList.forceActiveFocus());
        });
    }
    function openEntry(entry) {
        statusText = "";
        if (entry.is_dir) {
            if (providerName === "gdrive") cloudCrumbs = cloudCrumbs.concat([{label: entry.name, path: entry.target_path || entry.path}]);
            load(entry.target_path || entry.path);
        } else if (providerName !== "local") service.openCloudFile(providerName, entry);
        else service.request("open", {path: entry.path}, function(result, error) {
            notifyStatus(error || "", !!error);
            if (!error && result && host && !activeWorkCount) host.close();
        });
    }
    function runAction(op, entry) {
        statusText = "";
        service.request(op, {path: entry.path}, function(result, error) {
            notifyStatus(error || (result ? result.message : ""), !!error);
            if (!error && result && ["terminal", "reveal"].includes(op) && host && !activeWorkCount) host.close();
        });
    }
    function showActions(button, menu, selectedIndex) {
        const window = root.Window.window;
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
    function openActions(button, menu, entry) {
        if (menu.visible) { menu.close(); return; }
        menu.parent = button;
        if (activeActionsMenu && activeActionsMenu !== menu && activeActionsMenu.visible)
            activeActionsMenu.close();
        activeActionsMenu = menu;
        menu.anchorEntry = entry;
        menu.customActions = [];
        statusText = "";
        if (pendingDeletePath && pendingDeletePath !== entry.path) {
            pendingDeletePath = "";
            deleteConfirmation.stop();
        }
        const generation = ++actionMenuGeneration;
        if (providerName !== "local") { showActions(button, menu, 0); return; }
        service.request("custom_actions", {path: entry.path}, function(result, error) {
            if (generation !== actionMenuGeneration || !menu.anchorEntry || menu.anchorEntry.path !== entry.path) return;
            menu.customActions = error || !result ? [] : result.actions;
            if (error) notifyStatus(error, true);
            showActions(button, menu, pendingDeletePath === entry.path ? 4 : 0);
        });
    }
    function activateMenuAction(actionIndex, entry, menu) {
        if (actionIndex === 4 && pendingDeletePath !== entry.path) {
            root.confirmDelete(entry);
            Qt.callLater(() => {
                if (root.pendingDeletePath === entry.path && !menu.visible)
                    root.openActions(menu.anchorButton, menu, entry);
            });
            return;
        }
        if (actionIndex >= 5) {
            const customAction = menu.customActions[actionIndex - 5];
            menu.close();
            if (customAction) runCustomAction(customAction, entry);
            return;
        }
        menu.close();
        if (actionIndex === 0) root.openEntry(entry);
        else if (actionIndex === 1) root.runAction("terminal", entry);
        else if (actionIndex === 2) root.runAction("reveal", entry);
        else if (actionIndex === 3) root.copyPath(entry.path);
        else if (actionIndex === 4) root.confirmDelete(entry);
    }
    function runCustomAction(action, entry) {
        statusText = "";
        pendingActionStarts++;
        updateActionRetention();
        service.request("custom_action", {path: entry.path, index: action.index}, function(result, error) {
            pendingActionStarts = Math.max(0, pendingActionStarts - 1);
            if (error) {
                notifyStatus(error, true);
                updateActionRetention();
                return;
            }
            notifyStatus(result ? result.message : "", false);
            if (result && result.job_id !== undefined) {
                activeActionJobs = activeActionJobs.concat([{jobId: result.job_id, name: action.name}]);
            }
            updateActionRetention();
        });
    }
    function updateActionRetention() {
        if (host) host.requestKeepRunning("files", activeWorkCount > 0);
    }
    function pollActionJobs() {
        for (const job of activeActionJobs.slice()) {
            const key = String(job.jobId);
            if (pollingActionJobs[key]) continue;
            const polling = Object.assign({}, pollingActionJobs);
            polling[key] = true;
            pollingActionJobs = polling;
            service.request("custom_action_status", {job_id: job.jobId}, function(result, error) {
                const nextPolling = Object.assign({}, pollingActionJobs);
                delete nextPolling[key];
                pollingActionJobs = nextPolling;
                if (error) {
                    notifyStatus(error, true);
                    activeActionJobs = activeActionJobs.filter(item => item.jobId !== job.jobId);
                    updateActionRetention();
                    return;
                }
                if (!result || !result.finished) return;
                activeActionJobs = activeActionJobs.filter(item => item.jobId !== job.jobId);
                notifyStatus(result.returncode === 0
                    ? "Finished " + job.name
                    : result.returncode === null
                        ? "Stopped tracking " + job.name
                        : job.name + " exited with code " + result.returncode, result.returncode !== 0 && result.returncode !== null);
                updateActionRetention();
            });
        }
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
            notifyStatus(error || (result ? "Moved " + entry.name + " to Trash" : ""), !!error);
            if (!error && result) root.load(currentPath);
        });
    }
    function goUp() {
        if (providerName === "gdrive") {
            if (cloudCrumbs.length > 1) jump(cloudCrumbs[cloudCrumbs.length - 2].path);
        } else if (currentPath !== rootPath) load(currentPath.substring(0, currentPath.lastIndexOf("/")) || rootPath);
    }
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
    Timer {
        interval: 1000
        repeat: true
        running: root.activeActionJobs.length > 0
        onTriggered: root.pollActionJobs()
    }

    FilesService {
        id: service
        onJobStartFailed: message => activity.notify(message, true)
        onExternalFileOpened: { if (root.host) root.host.hide(); }
        onJobFinished: job => {
            if (job.title === "Connect Google Drive") driveCallback.close();
            activity.notify(job.error || (job.result ? job.result.message : "Transfer complete"), job.state === "failed");
            if (job.state === "finished") {
                if (job.result && job.result.opened && root.host) {
                    service.awaitingEditSnapshot = true;
                    service.pollEdits();
                    root.host.hide();
                } else root.load(root.currentPath);
            }
        }
        onFailed: message => activity.notify(message, true)
    }
    OperationCenter {
        id: activity
        objectName: "filesActivity"
        notificationTitle: "Files"
        parent: root
        jobs: service.jobs.map(job => job.kind === "authorization" && job.state === "running" && !job.cancel_requested ? Object.assign({}, job, {actionLabel: "Finish sign-in"}) : job).concat(service.editSessions).concat(root.activeActionJobs.map(job => ({job_id:"action:" + job.jobId, title:job.name, state:"running", detail:"Running file action", cancellable:false, done:0, total:0})))
        retryAvailable: !!root.errorText
        retryText: root.folderRetryText
        onRetryRequested: root.retryFolder()
        onCancelRequested: jobId => service.cancelJob(jobId)
        onSecondaryActionRequested: job => service.editSessionAction(job.job_id, true)
        onActionRequested: job => {
            if (job.kind === "editing") service.editSessionAction(job.job_id);
            else if (job.kind === "authorization" && job.state === "running") root.finishDriveSignIn();
            else if (job.title === "Connect Google Drive") root.connectDrive();
            else service.retryJob(job.job_id);
        }
    }
    Dialog {
        id: driveCallback
        objectName: "driveCallbackDialog"
        property bool submitting: false
        parent: root
        title: "Finish Google sign-in"
        modal: true; focus: true; popupType: Popup.Item
        x: (root.width - width) / 2; y: (root.height - height) / 2
        width: Math.min(500, root.width - 24)
        onOpened: callbackAddress.forceActiveFocus()
        onClosed: callbackAddress.clear()
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                Layout.fillWidth: true
                text: "If your browser could not reach the local page after Google consent, copy the full address from that failed page and paste it here. Use the current sign-in attempt."
                wrapMode: Text.WordWrap
                color: Theme.text
            }
            TextField {
                id: callbackAddress
                objectName: "driveCallbackAddress"
                Layout.fillWidth: true
                placeholderText: "http://127.0.0.1:…"
                echoMode: TextInput.PasswordEchoOnEdit
                color: Theme.text; placeholderTextColor: Theme.muted
                font.family: Theme.font; font.pixelSize: Theme.sp(14)
                enabled: !driveCallback.submitting
                background: Rectangle { color: Theme.raised; border.color: callbackAddress.activeFocus ? Theme.accent : Theme.border; radius: Theme.controlRadius }
                onAccepted: root.submitDriveCallback()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Action { text: "Cancel"; onClicked: driveCallback.close() }
                Action { text: driveCallback.submitting ? "Connecting…" : "Finish sign-in"; highlighted: true; enabled: !!callbackAddress.text.trim() && !driveCallback.submitting; onClicked: root.submitDriveCallback() }
            }
        }
    }
    DestinationPicker {
        id: destinationPicker
        parent: root
        service: root.fileWorker
        onChosen: (provider, path, move) => service.startJob("transfer", {
            source: sourceProvider, path: sourceEntry.path, destination: provider, target: path, move: move,
            title: (move ? "Move " : "Copy ") + sourceEntry.name
        })
    }
    Dialog {
        id: newFolder
        parent: root
        title: "New folder"
        modal: true; focus: true; popupType: Popup.Item
        x: (root.width - width) / 2; y: (root.height - height) / 2
        width: Math.min(420, root.width - 24)
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: folderName.forceActiveFocus()
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
        contentItem: TextField {
            id: folderName
            placeholderText: "Folder name"
            color: Theme.text; placeholderTextColor: Theme.muted
            font.family: Theme.font; font.pixelSize: Theme.sp(14)
            background: Rectangle { color: Theme.raised; border.color: folderName.activeFocus ? Theme.accent : Theme.border; radius: Theme.controlRadius }
            onAccepted: newFolder.accept()
        }
        onAccepted: service.request("mkdir", {provider: root.providerName, path: root.currentPath, name: folderName.text.trim()}, (result, error) => {
            activity.notify(error || result.message, !!error);
            if (!error) root.load(root.currentPath);
        })
    }
    Shortcut { sequence: "Ctrl+R"; onActivated: root.load(root.currentPath) }
    Shortcut { sequence: "Alt+Up"; onActivated: root.goUp() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: root.createFolder() }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [{id:"local", name:"Local", icon:"hard-drive"}, {id:"nextcloud", name:"Nextcloud", icon:"", artwork:Qt.resolvedUrl("../../assets/brands/nextcloud.svg")}, {id:"gdrive", name:"Google Drive", icon:"cloud"}]
            delegate: Action {
                required property var modelData
                text: modelData.name
                iconName: modelData.icon
                iconArtwork: modelData.artwork || ""
                highlighted: root.providerName === modelData.id
                onClicked: { if (root.providerName !== modelData.id) root.switchProvider(modelData.id); }
            }
        }
        Item { Layout.fillWidth: true }
        Action { objectName: "connectGoogleDrive"; visible: root.providerName === "gdrive"; iconName: "link"; text: root.driveSignInActive ? "Continue Google sign-in" : "Connect Google Drive"; enabled: !service.startingJobs; onClicked: root.connectDrive() }
        Action { visible: root.providerName === "gdrive" && root.driveSignInActive; iconName: "link"; text: "Finish sign-in"; onClicked: root.finishDriveSignIn() }
        Action { iconName: "folder-plus"; text: "New folder"; enabled: !!root.currentPath && !root.errorText && !root.loading; onClicked: root.createFolder() }
        Action { iconName: "download"; text: root.activeWorkCount ? "Activity (" + root.activeWorkCount + ")" : "Activity"; onClicked: activity.open() }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IconButton { iconName: "house"; text: "Go to home"; onClicked: root.jump(root.rootPath) }
        IconButton { iconName: "arrow-up"; text: "Go to parent folder"; enabled: root.providerName === "gdrive" ? root.cloudCrumbs.length > 1 : root.currentPath !== root.rootPath; onClicked: root.goUp() }
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
                            onClicked: root.jump(modelData.path)
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
        IconButton { visible: root.providerName === "local"; iconName: root.showHidden ? "eye-off" : "eye"; text: root.showHidden ? "Hide hidden files" : "Show hidden files"; onClicked: root.showHidden = !root.showHidden }
        IconButton { visible: root.providerName === "local"; iconName: "folder-open"; text: "Open this folder in the file manager"; enabled: !!root.currentPath; onClicked: root.runAction("reveal", {path: root.currentPath}) }
        IconButton { visible: root.providerName === "local"; iconName: "copy"; text: "Copy current folder path"; enabled: !!root.currentPath; onClicked: root.copyPath(root.currentPath) }
        IconButton { iconName: "refresh-cw"; text: "Refresh"; onClicked: root.load(root.currentPath) }
    }
    RowLayout {
        Layout.fillWidth: true
        SearchField { id: search; Layout.fillWidth: true; placeholderText: "Search this folder…" }
        Label { text: root.visibleEntries.length + (root.visibleEntries.length === 1 ? " item" : " items"); color: Theme.muted }
    }

    ListView {
        id: fileList
        objectName: "filesList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        enabled: !root.loading && !root.errorText
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
            Label { anchors.right: gear.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.size_label; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
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
                onClicked: root.openActions(gear, actions, row.modelData)
                Keys.onLeftPressed: (event) => { root.goUp(); fileList.forceActiveFocus(); event.accepted = true; }
                Keys.onRightPressed: (event) => { root.openActions(gear, actions, row.modelData); event.accepted = true; }
                Keys.onSpacePressed: (event) => { root.openActions(gear, actions, row.modelData); event.accepted = true; }
                Keys.onUpPressed: { root.moveSelection(-1); fileList.forceActiveFocus(); }
                Keys.onDownPressed: { root.moveSelection(1); fileList.forceActiveFocus(); }
                Menu {
                    id: actions
                    property var anchorButton: gear
                    popupType: Popup.Item
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    width: 260
                    property var customActions: []
                    property var anchorEntry: null
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
                        visible: root.providerName === "local"
                        enabled: visible
                        height: visible ? 42 : 0
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
                        visible: root.providerName === "local"
                        enabled: visible
                        height: visible ? 42 : 0
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
                        visible: root.providerName === "local"
                        enabled: visible
                        height: visible ? 42 : 0
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
                        visible: root.providerName === "local"
                        enabled: visible
                        height: visible ? 42 : 0
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
                    MenuItem { text: "Copy to…"; onTriggered: root.chooseTransfer(row.modelData, root.providerName === "local" ? "local" : "nextcloud", false) }
                    MenuItem { text: "Move to…"; onTriggered: root.chooseTransfer(row.modelData, "local", true) }
                    MenuItem {
                        text: "Open in browser"
                        visible: root.providerName === "gdrive" && !!row.modelData.web_url
                        height: visible ? implicitHeight : 0
                        onTriggered: Browser.open(row.modelData.web_url, "files", "", root.host)
                    }
                    MenuSeparator {
                        visible: actions.customActions.length > 0
                        implicitHeight: 9
                        contentItem: Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: Theme.border
                        }
                    }
                    Repeater {
                        model: actions.customActions
                        delegate: MenuItem {
                            id: customMenuItem
                            required property var modelData
                            required property int index
                            text: modelData.name
                            implicitHeight: 42
                            leftPadding: 12; rightPadding: 12
                            contentItem: Label {
                                text: customMenuItem.text
                                color: customMenuItem.highlighted ? Theme.accent : Theme.text
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            background: Rectangle { color: customMenuItem.highlighted ? Theme.raised : "transparent" }
                            onTriggered: root.activateMenuAction(5 + index, row.modelData, actions)
                            Keys.onReturnPressed: (event) => { root.activateMenuAction(5 + index, row.modelData, actions); event.accepted = true; }
                            Keys.onEnterPressed: (event) => { root.activateMenuAction(5 + index, row.modelData, actions); event.accepted = true; }
                            Keys.onRightPressed: (event) => { root.activateMenuAction(5 + index, row.modelData, actions); event.accepted = true; }
                            Keys.onLeftPressed: (event) => { actions.close(); event.accepted = true; }
                            Keys.onSpacePressed: (event) => { actions.close(); event.accepted = true; }
                        }
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
        Keys.onSpacePressed: (event) => { if (currentItem && currentIndex >= 0) root.openActions(currentItem.actionButton, currentItem.actionMenu, currentItem.modelData); event.accepted = true; }
        Label {
            anchors.centerIn: parent
            width: Math.min(500, parent.width - 32)
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            visible: root.loading || (!root.errorText && !root.visibleEntries.length)
            text: root.loading ? "Loading files…" : search.text.trim() ? "No matching files." : root.showHidden ? "This folder is empty." : "This folder is empty. Hidden files are not shown."
            color: root.errorText ? Theme.danger : Theme.muted
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        Item { Layout.fillWidth: true }
        Action { objectName: "folderRetry"; visible: !!root.errorText; text: root.folderRetryText; iconName: "refresh-cw"; onClicked: root.retryFolder() }
        Action { visible: !!root.nextCursor && !root.errorText; enabled: !root.loading; text: "Load more"; onClicked: root.load(root.currentPath, true) }
    }
}
