import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../widgets" as W

Item {
    id: root
    objectName: "projectsBrowser"
    property var host
    property var projects: []
    property string projectsPath: ""
    property bool missingRoot: false
    property bool loading: true
    property bool busy: false
    property bool miseAvailable: false
    property var templates: []
    property string selectedTemplate: "empty"
    property string createdPath: ""
    property string setupId: ""
    property string setupScript: ""
    property string setupProjectPath: ""
    property bool setupDone: false
    property bool setupSuccess: false
    property string cloneJob: ""
    property string clonePhase: ""
    property var clonePercent: null
    property var selectedProject: ({})
    property string actionMode: ""
    property string actionPhase: "form"
    property string actionError: ""
    property bool actionBusy: false
    property var cleanupEntries: []
    property var cleanupSelection: []
    property bool configuredMise: false
    property string errorText: ""
    property string formError: ""
    property int generation: 0
    readonly property var matches: projects.filter(project => (project.name + " " + project.path + " " + project.badges.map(badge => badge.label).join(" ")).toLowerCase().includes(search.text.trim().toLowerCase()))

    function activate() { search.forceActiveFocus(); }
    function iconSource(name) { return name ? Qt.resolvedUrl("../../assets/devicon/" + name + ".svg") : ""; }
    function openedLabel(value) {
        if (!value) return "Not opened yet";
        const date = new Date(value);
        return "Opened " + date.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }
    function refresh(forceProfiles = false) {
        const requestGeneration = ++generation;
        loading = true;
        errorText = "";
        service.request(forceProfiles ? "refreshAllProfiles" : "list", {}, (result, error) => {
            if (requestGeneration !== generation) return;
            loading = false;
            if (error) { errorText = error; return; }
            projectsPath = result.root;
            missingRoot = result.missing;
            projects = result.projects || [];
            templates = result.templates || [];
            miseAvailable = !!result.mise;
            errorText = result.warning || "";
        });
    }
    function refreshProject(project) {
        const requestGeneration = ++generation;
        loading = true;
        errorText = "";
        service.request("refreshProfile", {path: project.path}, (result, error) => {
            if (requestGeneration !== generation) return;
            if (error) { loading = false; errorText = error; return; }
            refresh();
        });
    }
    function openProject(project) {
        if (busy) return;
        errorText = "";
        busy = true;
        service.request("open", {path: project.path}, (result, error) => {
            busy = false;
            if (error) { errorText = error; return; }
            if (result && host) host.close();
        });
    }
    function suggestedName(url) {
        const last = url.trim().replace(/\/+$/, "").split(/[/:]/).pop() || "";
        return last.replace(/\.git$/i, "");
    }
    function filteredTemplates(category) {
        const query = templateSearch.text.trim().toLowerCase();
        return templates.filter(item => item.category === category && (miseAvailable || item.id === "empty" || item.id === "vite-plus")
                                && (item.label + " " + item.description + " " + item.category).toLowerCase().includes(query));
    }
    function openMenu(button, menu) {
        const window = root.Window.window;
        if (!window) { menu.open(); return; }
        const point = button.mapToItem(window.contentItem, 0, 0);
        const x = Math.max(8, Math.min(point.x + button.width - menu.width, window.width - menu.width - 8));
        const below = point.y + button.height;
        const height = menu.implicitHeight || 220;
        const y = below + height < window.height - 8 ? below : Math.max(8, point.y - height);
        menu.popup(window.contentItem, x, y);
    }
    function showForm(nextMode) {
        formError = "";
        if (nextMode === "clone") {
            cloneName.text = ""; cloneUrl.text = ""; cloneMode.currentIndex = 0;
            cloneJob = ""; clonePhase = ""; clonePercent = null;
            cloneDialog.open();
            Qt.callLater(() => cloneUrl.forceActiveFocus());
        } else {
            newName.text = ""; templateSearch.text = ""; selectedTemplate = "empty";
            createdPath = ""; setupId = ""; setupScript = ""; setupProjectPath = ""; setupDone = false;
            newDialog.open();
            Qt.callLater(() => newName.forceActiveFocus());
        }
    }
    function startSetup(result) {
        setupId = result.setupId || "";
        setupScript = result.setupScript || "";
        setupProjectPath = result.path || selectedProject.path || "";
        setupDone = !setupId;
        setupSuccess = !setupId;
    }
    function submitCreate() {
        if (busy || !newName.text.trim()) return;
        formError = "";
        busy = true;
        service.request("create", {name: newName.text.trim(), template: selectedTemplate}, (result, error) => {
            busy = false;
            if (error) { formError = error; return; }
            createdPath = result.path;
            startSetup(result);
            refresh();
        });
    }
    function submitClone() {
        if (busy || !cloneName.text.trim() || !cloneUrl.text.trim()) return;
        formError = ""; busy = true; clonePhase = "Preparing clone";
        service.request("cloneStart", {url: cloneUrl.text.trim(), name: cloneName.text.trim(),
                                        mode: cloneMode.currentValue}, (result, error) => {
            if (error) { busy = false; formError = error; return; }
            cloneJob = result.id;
        });
    }
    function cancelClone() {
        if (!cloneJob) return;
        service.request("cloneCancel", {job: cloneJob}, (result, error) => {
            if (error) formError = error;
        });
    }
    function showProjectAction(kind, project) {
        selectedProject = project;
        actionMode = kind; actionPhase = "form"; actionError = "";
        actionBusy = ["notes", "cleanup", "bootstrap"].includes(kind);
        cleanupEntries = []; cleanupSelection = []; configuredMise = false;
        notesField.text = ""; inferredField.text = ""; confirmationField.text = "";
        actionDialog.open();
        if (kind === "notes") service.request("notes", {path: project.path}, (result, error) => {
            actionBusy = false; actionError = error; if (!error) notesField.text = result.notes;
        });
        if (kind === "cleanup") service.request("cleanupPreview", {path: project.path}, (result, error) => {
            actionBusy = false; actionError = error;
            if (!error) { cleanupEntries = result.entries; cleanupSelection = result.entries.map(item => item.path); }
        });
        if (kind === "bootstrap") service.request("bootstrapPlan", {path: project.path}, (result, error) => {
            actionBusy = false; actionError = error;
            if (!error) { configuredMise = result.configured; inferredField.text = result.tools.join(" "); }
        });
    }
    function showGlobalAction(kind) {
        selectedProject = ({}); actionMode = kind; actionPhase = "form";
        actionError = ""; actionBusy = false; actionDialog.open();
        if (kind === "globalSpace") {
            cacheChoice.checked = true; miseChoice.checked = false;
            toolsChoice.checked = false; toolConfirmationField.text = "";
        }
        if (kind === "globalUpdate") runGlobal("update");
        if (kind === "globalPrune") runGlobal("prune");
    }
    function runGlobal(kind) {
        actionBusy = true; actionError = "";
        service.request("miseGlobal", {action: kind}, (result, error) => {
            actionBusy = false;
            if (error) actionError = error;
            else { actionPhase = "result"; actionOutput.text = result.output || result.message; }
        });
    }
    function runFreeSpace() {
        actionBusy = true; actionError = "";
        service.request("freeSpace", {caches: cacheChoice.checked,
                                      miseTools: miseChoice.checked,
                                      otherTools: toolsChoice.checked,
                                      confirmation: toolConfirmationField.text}, (result, error) => {
            actionBusy = false;
            if (error) actionError = error;
            else { actionPhase = "result"; actionOutput.text = result.output || result.message; }
        });
    }
    function startProjectMise(kind) {
        actionBusy = true; actionError = "";
        service.request("prepareMise", {path: selectedProject.path, action: kind,
                                         tools: inferredField.text.trim()}, (result, error) => {
            actionBusy = false;
            if (error) { actionError = error; return; }
            actionPhase = "terminal";
            startSetup(result);
        });
    }
    function saveProjectNotes() {
        actionBusy = true; actionError = "";
        service.request("saveNotes", {path: selectedProject.path, notes: notesField.text}, (result, error) => {
            actionBusy = false;
            if (error) actionError = error;
            else actionDialog.close();
        });
    }
    function cleanProject() {
        actionBusy = true; actionError = "";
        service.request("cleanup", {path: selectedProject.path, selected: cleanupSelection}, (result, error) => {
            actionBusy = false;
            if (error) actionError = error;
            else { actionPhase = "result"; actionOutput.text = "Removed " + result.count + " ignored entries."; refresh(); }
        });
    }
    function trashProject() {
        actionBusy = true; actionError = "";
        service.request("trash", {path: selectedProject.path, confirmation: confirmationField.text}, (result, error) => {
            actionBusy = false;
            if (error) actionError = error;
            else { actionDialog.close(); refresh(); }
        });
    }
    Component.onCompleted: refresh()
    ProjectsService { id: service; onFailed: message => { root.loading = false; root.errorText = message; } }
    Timer {
        interval: 600; repeat: true; running: !!root.cloneJob
        onTriggered: service.request("cloneStatus", {job: root.cloneJob}, (result, error) => {
            if (error) { root.formError = error; root.busy = false; root.cloneJob = ""; return; }
            root.clonePhase = result.phase;
            root.clonePercent = result.percent;
            if (result.done) {
                root.cloneJob = ""; root.busy = false;
                if (result.cancelled) root.formError = "Clone cancelled.";
                else if (result.error) root.formError = result.error;
                else { cloneDialog.close(); root.refresh(); }
            }
        })
    }
    Timer {
        interval: 650; repeat: true; running: !!root.setupId && !root.setupDone
        onTriggered: service.request("setupStatus", {setupId: root.setupId}, (result, error) => {
            if (error) {
                if (newDialog.visible) root.formError = error;
                else root.actionError = error;
                root.setupId = "";
                return;
            }
            if (result.done) {
                root.setupDone = true; root.setupSuccess = result.success; root.setupId = "";
                if (root.setupProjectPath) root.refreshProject({path: root.setupProjectPath});
                else root.refresh();
            }
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.moduleMargin
        anchors.rightMargin: Theme.moduleMargin
        anchors.topMargin: 22
        anchors.bottomMargin: Theme.moduleMargin
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                W.Heading { text: "WORKSPACE" }
                W.Label { text: "Projects"; font.pixelSize: 28; font.bold: true }
                W.Label { text: root.projectsPath || "Your XDG Projects folder"; color: Theme.muted; elide: Text.ElideMiddle; Layout.fillWidth: true }
            }
            W.Action { text: "Git Clone"; iconName: "folder-git-2"; enabled: !root.busy; onClicked: root.showForm("clone") }
            W.Action { text: "New Project"; iconName: "folder-plus"; enabled: !root.busy; onClicked: root.showForm("create") }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            W.SearchField {
                id: search
                Layout.fillWidth: true
                placeholderText: "Search projects and technologies…"
                onAccepted: { if (root.matches.length) root.openProject(root.matches[0]); }
            }
            W.Label {
                text: root.loading ? "Loading…" : root.matches.length + (root.matches.length === 1 ? " project" : " projects")
                color: Theme.muted
            }
            W.IconButton { iconName: "refresh-cw"; text: "Refresh projects and technologies"; onClicked: root.refresh(true) }
        }
        RowLayout {
            Layout.fillWidth: true
            W.Label { text: "Recent Projects"; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
            W.IconButton {
                id: recentOptions
                iconName: "ellipsis-vertical"; iconSize: 18
                text: "Recent Projects options"
                onClicked: root.openMenu(recentOptions, recentMenu)
                Menu {
                    id: recentMenu
                    popupType: Popup.Item
                    width: 230
                    background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
                    MenuAction { text: "Update installed tools"; enabled: root.miseAvailable; onTriggered: root.showGlobalAction("globalUpdate") }
                    MenuAction { text: "Prune unused tools"; enabled: root.miseAvailable; onTriggered: root.showGlobalAction("globalPrune") }
                    MenuAction { text: "Free up space…"; destructive: true; onTriggered: root.showGlobalAction("globalSpace") }
                }
            }
        }
        W.Label {
            visible: !!root.errorText
            Layout.fillWidth: true
            text: root.errorText
            color: Theme.danger
            wrapMode: Text.Wrap
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: root.loading ? [] : root.matches
            keyNavigationEnabled: true
            W.WheelScroll { view: list; pixelsPerNotch: 280 }
            delegate: W.Action {
                id: card
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 106
                text: modelData.name
                enabled: !root.busy
                highlighted: list.activeFocus && list.currentIndex === index
                onClicked: root.openProject(modelData)
                background: Rectangle {
                    radius: Theme.radius
                    color: card.down ? Theme.raised : card.hovered || card.highlighted ? Theme.accentSurface : Theme.surface
                    border.color: card.activeFocus || card.highlighted ? Theme.accent : Theme.border
                    border.width: 1
                }
                contentItem: RowLayout {
                    spacing: 16
                    Rectangle {
                        Layout.preferredWidth: 66; Layout.preferredHeight: 66
                        radius: Theme.radius
                        color: ["rust", "nextjs", "django", "prisma", "astro", "denojs"].includes(card.modelData.symbol) && !card.modelData.logo ? "#d7d9df" : Theme.raised
                        border.color: Theme.border
                        W.Label {
                            visible: !projectImage.visible && !techImage.visible
                            anchors.centerIn: parent
                            text: card.modelData.name.charAt(0).toUpperCase()
                            font.pixelSize: 25; font.bold: true
                        }
                        Image {
                            id: techImage
                            visible: !projectImage.visible && !!card.modelData.symbol
                            anchors.centerIn: parent
                            width: 36; height: 36
                            source: visible ? root.iconSource(card.modelData.symbol) : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 72; sourceSize.height: 72
                        }
                        Image {
                            id: projectImage
                            visible: !!card.modelData.logo && status === Image.Ready
                            anchors.fill: parent; anchors.margins: 7
                            source: card.modelData.logo || ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 128; sourceSize.height: 128
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        W.Label { text: card.modelData.name; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
                        W.Label { text: card.modelData.path; color: Theme.muted; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        W.Label { text: root.openedLabel(card.modelData.opened); color: Theme.muted; font.pixelSize: 11 }
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: card.modelData.badges
                            delegate: Rectangle {
                                required property var modelData
                                width: 32; height: 32
                                radius: Theme.controlRadius
                                color: ["rust", "nextjs", "django", "prisma", "astro", "denojs"].includes(modelData.icon) ? "#d7d9df" : Theme.raised
                                border.color: Theme.border
                                Image {
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    source: root.iconSource(parent.modelData.icon)
                                    sourceSize.width: 40; sourceSize.height: 40
                                    fillMode: Image.PreserveAspectFit
                                }
                                ToolTip.visible: badgeHover.hovered
                                ToolTip.text: modelData.label
                                HoverHandler { id: badgeHover }
                            }
                        }
                    }
                    W.IconButton {
                        id: cardOptions
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
                        iconName: "ellipsis-vertical"; iconSize: 18
                        text: "Options for " + card.modelData.name
                        onClicked: root.openMenu(cardOptions, cardMenu)
                        Menu {
                            id: cardMenu
                            popupType: Popup.Item
                            width: 190
                            background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.controlRadius }
                            MenuAction { text: "Bootstrap"; enabled: root.miseAvailable; onTriggered: root.showProjectAction("bootstrap", card.modelData) }
                            MenuAction { text: "Update tools"; enabled: root.miseAvailable; onTriggered: root.showProjectAction("update", card.modelData) }
                            MenuAction { text: "Notes"; onTriggered: root.showProjectAction("notes", card.modelData) }
                            MenuAction { text: "Refresh"; onTriggered: root.refreshProject(card.modelData) }
                            MenuSeparator {}
                            MenuAction { text: "Cleanup files…"; destructive: true; onTriggered: root.showProjectAction("cleanup", card.modelData) }
                            MenuAction { text: "Delete…"; destructive: true; onTriggered: root.showProjectAction("trash", card.modelData) }
                        }
                    }
                }
            }
            W.Label {
                visible: !root.loading && !root.errorText && list.count === 0
                anchors.centerIn: parent
                text: root.missingRoot ? "Projects folder does not exist yet. Create a project to begin." : search.text ? "No projects match your search." : "No projects in this folder yet."
                color: Theme.muted
            }
            BusyIndicator { anchors.centerIn: parent; visible: root.loading; running: visible }
        }
    }

    Popup {
        id: newDialog
        modal: true; focus: true
        closePolicy: root.busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: Math.min(880, root.width - 32)
        height: Math.min(root.createdPath ? 660 : 720, root.height - 32)
        x: (root.width - width) / 2; y: (root.height - height) / 2
        padding: 20
        onClosed: {
            if (root.createdPath) {
                const abandoned = root.setupId;
                root.setupId = ""; root.setupScript = ""; root.setupProjectPath = "";
                if (abandoned) service.request("discardSetup", {setupId: abandoned}, () => {});
            }
        }
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.radius }
        contentItem: ColumnLayout {
            spacing: 12
            W.Label { text: root.createdPath ? "Building new project" : "New project"; font.pixelSize: 22; font.bold: true }
            W.Label {
                Layout.fillWidth: true
                text: root.createdPath ? root.createdPath : "Create inside " + (root.projectsPath || "your Projects folder") + ", then scaffold it in a live terminal."
                color: Theme.muted; elide: Text.ElideMiddle
            }
            ColumnLayout {
                visible: !root.createdPath
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 10
                W.Label { text: "Project name"; color: Theme.muted }
                W.SearchField { id: newName; Layout.fillWidth: true; placeholderText: "MyAwesomeIdea"; onAccepted: root.submitCreate() }
                W.Label { text: "Start from"; color: Theme.muted; font.bold: true }
                W.SearchField { id: templateSearch; Layout.fillWidth: true; placeholderText: "Filter frameworks and runtimes…" }
                W.Label {
                    visible: !root.miseAvailable
                    Layout.fillWidth: true
                    text: "Install mise to use managed toolchain templates. Empty projects and Vite+ (with vp installed) remain available."
                    color: Theme.muted; wrapMode: Text.Wrap
                }
                Flickable {
                    id: templateList
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; contentWidth: width; contentHeight: templateColumn.implicitHeight
                    W.WheelScroll { view: templateList; pixelsPerNotch: 280 }
                    ScrollBar.vertical: ScrollBar {}
                    Column {
                        id: templateColumn
                        width: templateList.width
                        spacing: 16
                        Repeater {
                            model: ["Basics", "Web", "Backend", "Native"]
                            delegate: Column {
                                id: categoryGroup
                                required property string modelData
                                width: templateColumn.width
                                visible: root.filteredTemplates(modelData).length > 0
                                spacing: 6
                                W.Label { text: categoryGroup.modelData.toUpperCase(); color: Theme.accent; font.pixelSize: 11; font.bold: true }
                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: root.filteredTemplates(categoryGroup.modelData)
                                        delegate: W.Action {
                                            id: templateCard
                                            required property var modelData
                                            width: Math.max(184, Math.floor((templateList.width - 24) / 4))
                                            height: 76
                                            text: modelData.label
                                            enabled: modelData.available && !root.busy
                                            highlighted: root.selectedTemplate === modelData.id
                                            onClicked: root.selectedTemplate = modelData.id
                                            background: Rectangle {
                                                radius: Theme.controlRadius
                                                color: templateCard.highlighted ? Theme.accentSurface : templateCard.hovered ? Theme.raised : Theme.background
                                                border.color: templateCard.highlighted ? Theme.accent : Theme.border
                                            }
                                            contentItem: RowLayout {
                                                spacing: 8
                                                Rectangle {
                                                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                                    radius: Theme.controlRadius; color: Theme.raised
                                                    Image {
                                                        id: starterIcon
                                                        anchors.centerIn: parent; width: 25; height: 25
                                                        source: ["folder", "hono"].includes(templateCard.modelData.icon) ? "" : root.iconSource(templateCard.modelData.icon)
                                                        fillMode: Image.PreserveAspectFit
                                                    }
                                                    W.Icon {
                                                        visible: templateCard.modelData.icon === "folder"
                                                        anchors.centerIn: parent; width: 22; height: 22; name: "folder"
                                                    }
                                                    W.Label {
                                                        visible: starterIcon.status !== Image.Ready && templateCard.modelData.icon !== "folder"
                                                        anchors.centerIn: parent
                                                        text: templateCard.modelData.label.charAt(0)
                                                        font.bold: true
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 2
                                                    W.Label { Layout.fillWidth: true; text: templateCard.modelData.label; font.bold: true; font.pixelSize: 12 }
                                                    W.Label {
                                                        Layout.fillWidth: true
                                                        text: templateCard.modelData.available ? templateCard.modelData.description : "Requires " + templateCard.modelData.requires
                                                        color: Theme.muted; font.pixelSize: 10
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                W.Label { visible: !!root.formError; Layout.fillWidth: true; text: root.formError; color: Theme.danger; wrapMode: Text.Wrap }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    W.Action { text: "Cancel"; enabled: !root.busy; onClicked: newDialog.close() }
                    W.Action {
                        text: root.busy ? "Creating…" : "Create project"
                        iconName: "folder-plus"; highlighted: true
                        enabled: !root.busy && !!newName.text.trim()
                        onClicked: root.submitCreate()
                    }
                }
            }
            ColumnLayout {
                visible: !!root.createdPath
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 10
                Rectangle {
                    visible: !!root.setupScript
                    Layout.fillWidth: true; Layout.fillHeight: true
                    color: Theme.background; radius: Theme.controlRadius; border.color: Theme.border
                    Loader {
                        anchors.fill: parent; anchors.margins: 8
                        active: !!root.setupScript && newDialog.visible
                        sourceComponent: ProjectTerminal {
                            projectPath: root.createdPath
                            scriptPath: root.setupScript
                        }
                    }
                }
                W.Label {
                    Layout.fillWidth: true
                    text: !root.setupScript ? "Empty project created." : !root.setupDone ? "Setup is running. Closing this dialog stops its terminal." : root.setupSuccess ? "Setup finished successfully." : "Setup exited with an error. The terminal remains available for repairs."
                    color: root.setupDone && !root.setupSuccess ? Theme.danger : Theme.muted
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    W.Action { text: "Back to projects"; onClicked: newDialog.close() }
                    W.Action { text: "Open in Zed"; iconName: "folder-open"; highlighted: true; onClicked: root.openProject({path: root.createdPath}) }
                }
            }
        }
    }

    Popup {
        id: cloneDialog
        modal: true; focus: true
        closePolicy: root.busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: Math.min(550, root.width - 32)
        x: (root.width - width) / 2; y: (root.height - height) / 2
        padding: 22
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.radius }
        contentItem: ColumnLayout {
            spacing: 12
            W.Label { text: "Git Clone"; font.pixelSize: 22; font.bold: true }
            W.Label { text: "Clone a Git repository into your Projects folder."; color: Theme.muted; Layout.fillWidth: true }
            W.Label { text: "Repository URL"; color: Theme.muted }
            W.SearchField {
                id: cloneUrl; Layout.fillWidth: true
                placeholderText: "https://github.com/owner/project.git"
                property string previousValue: ""
                onTextChanged: {
                    if (!cloneName.text || cloneName.text === root.suggestedName(previousValue))
                        cloneName.text = root.suggestedName(text);
                    previousValue = text;
                }
                onAccepted: root.submitClone()
            }
            W.Label { text: "Destination folder"; color: Theme.muted }
            W.SearchField { id: cloneName; Layout.fillWidth: true; placeholderText: "project"; onAccepted: root.submitClone() }
            W.Label { text: "Clone mode"; color: Theme.muted }
            W.Choice {
                id: cloneMode; Layout.fillWidth: true
                textRole: "label"; valueRole: "value"
                model: [
                    {label: "Full", value: "full"},
                    {label: "Blobless", value: "blobless"},
                    {label: "Shallow", value: "shallow"}
                ]
            }
            RowLayout {
                visible: root.busy && !!root.clonePhase
                Layout.fillWidth: true
                BusyIndicator { running: parent.visible; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                W.Label {
                    Layout.fillWidth: true
                    text: root.clonePhase + (root.clonePercent === null ? "…" : "… " + root.clonePercent + "%")
                    color: Theme.accent
                }
            }
            W.Label { visible: !!root.formError; Layout.fillWidth: true; text: root.formError; color: Theme.danger; wrapMode: Text.Wrap }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                W.Action { text: root.busy ? "Cancel clone" : "Cancel"; onClicked: root.busy ? root.cancelClone() : cloneDialog.close() }
                W.Action {
                    text: root.busy ? "Cloning…" : "Clone repository"
                    iconName: "folder-git-2"; highlighted: true
                    enabled: !root.busy && !!cloneUrl.text.trim() && !!cloneName.text.trim()
                    onClicked: root.submitClone()
                }
            }
        }
    }

    Popup {
        id: actionDialog
        modal: true; focus: true
        closePolicy: root.actionBusy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: Math.min(root.actionPhase === "terminal" ? 720 : 600, root.width - 32)
        height: Math.min(root.actionPhase === "terminal" || root.actionMode === "notes" || root.actionMode === "cleanup" ? 620 : root.actionMode === "globalSpace" ? 560 : 440, root.height - 32)
        x: (root.width - width) / 2; y: (root.height - height) / 2
        padding: 20
        onClosed: {
            if (root.actionPhase === "terminal") {
                const abandoned = root.setupId;
                root.setupId = ""; root.setupScript = ""; root.setupProjectPath = "";
                if (abandoned) service.request("discardSetup", {setupId: abandoned}, () => {});
            }
        }
        background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: Theme.radius }
        contentItem: ColumnLayout {
            spacing: 12
            W.Label {
                Layout.fillWidth: true
                text: root.actionMode === "globalUpdate" ? "Update installed tools"
                    : root.actionMode === "globalPrune" ? "Prune unused tools"
                    : root.actionMode === "globalSpace" ? "Free up space"
                    : root.actionMode === "bootstrap" ? "Bootstrap " + root.selectedProject.name
                    : root.actionMode === "update" ? "Update tools for " + root.selectedProject.name
                    : root.actionMode === "notes" ? "Notes for " + root.selectedProject.name
                    : root.actionMode === "cleanup" ? "Cleanup files in " + root.selectedProject.name
                    : "Delete " + root.selectedProject.name + "?"
                font.pixelSize: 21; font.bold: true
            }
            W.Label {
                Layout.fillWidth: true
                text: root.actionMode === "notes" ? "Private notes stored in Zephyrus Shell application data."
                    : root.actionMode === "cleanup" ? "Select ignored build artifacts and caches to remove. Local configuration is excluded."
                    : root.actionMode === "trash" ? "Move this project folder to Trash. You can restore it later."
                    : root.actionMode === "bootstrap" ? "Install the project's toolchain with mise."
                    : root.actionMode === "update" ? "Upgrade project-local tools within their configured ranges."
                    : root.actionMode === "globalSpace" ? "Choose reinstallable caches or tools to remove. Project files and settings stay in place."
                    : "Manage installed Mise tools."
                color: Theme.muted; wrapMode: Text.Wrap
            }
            ColumnLayout {
                visible: root.actionPhase === "form" && root.actionMode === "bootstrap"
                Layout.fillWidth: true; spacing: 8
                W.Label { text: root.actionBusy ? "Inspecting this project…" : root.configuredMise ? "A mise configuration was found. Trust and install its tools." : "Inferred tools (edit as needed)"; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                W.SearchField { id: inferredField; visible: !root.configuredMise && !root.actionBusy; Layout.fillWidth: true; placeholderText: "node@lts python@latest" }
                W.Label { text: root.configuredMise ? "mise trust --yes && mise install --yes" : "mise use --yes --env local …"; color: Theme.muted; font.pixelSize: 11 }
            }
            W.Label {
                visible: root.actionPhase === "form" && root.actionMode === "update"
                text: "mise trust --yes && mise upgrade --local"
                color: Theme.muted
            }
            TextArea {
                id: notesField
                visible: root.actionPhase === "form" && root.actionMode === "notes"
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.text; font.family: "monospace"; font.pixelSize: 13
                wrapMode: TextEdit.Wrap
                enabled: !root.actionBusy
                placeholderText: "Write anything you want to remember about this project…"
                background: Rectangle { color: Theme.background; border.color: Theme.border; radius: Theme.controlRadius }
            }
            ColumnLayout {
                visible: root.actionPhase === "form" && root.actionMode === "cleanup"
                Layout.fillWidth: true; Layout.fillHeight: true
                W.Label { text: root.actionBusy ? "Finding cleanup candidates…" : root.cleanupEntries.length ? root.cleanupEntries.length + " ignored entries found" : "No ignored files to clean up."; color: Theme.muted }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Column {
                        width: parent.width
                        Repeater {
                            model: root.cleanupEntries
                            delegate: ProjectCheck {
                                required property var modelData
                                width: parent.width
                                text: modelData.path
                                checked: root.cleanupSelection.includes(modelData.path)
                                onToggled: {
                                    root.cleanupSelection = checked
                                        ? root.cleanupSelection.concat([modelData.path])
                                        : root.cleanupSelection.filter(path => path !== modelData.path);
                                }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                visible: root.actionPhase === "form" && root.actionMode === "trash"
                Layout.fillWidth: true; spacing: 7
                W.Label { text: "Type " + root.selectedProject.name + " to confirm"; color: Theme.muted }
                W.SearchField { id: confirmationField; Layout.fillWidth: true; placeholderText: root.selectedProject.name || "" }
            }
            ColumnLayout {
                visible: root.actionPhase === "form" && root.actionMode === "globalSpace"
                Layout.fillWidth: true; spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    ProjectCheck { id: cacheChoice; text: "Downloaded packages and build caches"; checked: true }
                    W.Label { Layout.fillWidth: true; Layout.leftMargin: 32; text: "Caches from npm, Bun, Cargo, Gradle, Python, and other development tools."; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    ProjectCheck { id: miseChoice; text: "Tools installed with Mise"; checked: false; enabled: root.miseAvailable }
                    W.Label { Layout.fillWidth: true; Layout.leftMargin: 32; text: "Removes all Mise tool versions and its cache. Your project setup files remain."; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    ProjectCheck { id: toolsChoice; text: "Other installed developer tools"; checked: false }
                    W.Label { Layout.fillWidth: true; Layout.leftMargin: 32; text: "Removes Bun, Deno, and Rustup installations. You can reinstall them later."; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap }
                }
                W.Label {
                    visible: miseChoice.checked || toolsChoice.checked
                    text: "Type REMOVE TOOLS to confirm tool removal"; color: Theme.danger
                }
                W.SearchField {
                    visible: miseChoice.checked || toolsChoice.checked
                    id: toolConfirmationField
                    Layout.fillWidth: true; placeholderText: "REMOVE TOOLS"
                }
            }
            Rectangle {
                visible: root.actionPhase === "terminal"
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.background; radius: Theme.controlRadius; border.color: Theme.border
                Loader {
                    anchors.fill: parent; anchors.margins: 8
                    active: root.actionPhase === "terminal" && actionDialog.visible && !!root.setupScript
                    sourceComponent: ProjectTerminal {
                        projectPath: root.selectedProject.path || ""
                        scriptPath: root.setupScript
                    }
                }
            }
            W.Label {
                visible: root.actionPhase === "terminal"
                Layout.fillWidth: true
                text: !root.setupDone ? "Mise is running. Closing this dialog stops its terminal." : root.setupSuccess ? "Mise finished successfully." : "Mise exited with an error. Review the terminal output."
                color: root.setupDone && !root.setupSuccess ? Theme.danger : Theme.muted
                wrapMode: Text.Wrap
            }
            W.Label {
                id: actionOutput
                visible: root.actionPhase === "result"
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.muted; wrapMode: Text.Wrap
            }
            W.Label { visible: !!root.actionError; Layout.fillWidth: true; text: root.actionError; color: Theme.danger; wrapMode: Text.Wrap }
            BusyIndicator { visible: root.actionBusy; running: visible; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                W.Action { text: root.actionPhase === "terminal" || root.actionPhase === "result" ? "Close" : "Cancel"; enabled: !root.actionBusy; onClicked: actionDialog.close() }
                W.Action { visible: root.actionMode === "notes" && root.actionPhase === "form"; text: "Save notes"; highlighted: true; enabled: !root.actionBusy; onClicked: root.saveProjectNotes() }
                W.Action { visible: root.actionMode === "bootstrap" && root.actionPhase === "form"; text: "Bootstrap"; highlighted: true; enabled: !root.actionBusy && (root.configuredMise || !!inferredField.text.trim()); onClicked: root.startProjectMise("bootstrap") }
                W.Action { visible: root.actionMode === "update" && root.actionPhase === "form"; text: "Update tools"; highlighted: true; enabled: !root.actionBusy; onClicked: root.startProjectMise("update") }
                W.Action { visible: root.actionMode === "cleanup" && root.actionPhase === "form"; text: "Cleanup selected"; destructive: true; enabled: !root.actionBusy && root.cleanupSelection.length > 0; onClicked: root.cleanProject() }
                W.Action { visible: root.actionMode === "trash" && root.actionPhase === "form"; text: "Move to Trash"; destructive: true; enabled: !root.actionBusy && confirmationField.text === root.selectedProject.name; onClicked: root.trashProject() }
                W.Action { visible: root.actionMode === "globalSpace" && root.actionPhase === "form"; text: "Free up space"; destructive: true; enabled: !root.actionBusy && (cacheChoice.checked || miseChoice.checked || toolsChoice.checked) && (!(miseChoice.checked || toolsChoice.checked) || toolConfirmationField.text === "REMOVE TOOLS"); onClicked: root.runFreeSpace() }
            }
        }
    }
}
