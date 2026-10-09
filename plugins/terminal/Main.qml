import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../files"
import "../../core"
import "../../services"
import "../../widgets"

FocusScope {
    id: root
    property var host
    property int currentIndex: 0
    property int nextTab: 0
    property int sessionsRevision: 0
    property var commands: []
    property bool commandsLoading: true
    property string commandsError: ""
    property string message: ""
    property alias commandsMenu: commandsPopup
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/zephyrus-shell/terminal.json"
    readonly property int tabCount: tabs.count
    readonly property var currentTerminal: {
        sessionsRevision;
        const holder = sessions.itemAt(currentIndex);
        return holder ? holder.view : null;
    }

    function activate() {
        if (!tabs.count) addTab();
        if (currentTerminal) currentTerminal.forceTerminalFocus();
    }
    function addTab() {
        tabs.append({number: ++nextTab});
        currentIndex = tabs.count - 1;
        message = "";
        Qt.callLater(activate);
    }
    function selectTab(index) {
        currentIndex = index;
        message = "";
        Qt.callLater(activate);
    }
    function closeTab(index) {
        if (index < 0 || index >= tabs.count) return;
        tabs.remove(index);
        if (index < currentIndex) currentIndex--;
        currentIndex = Math.max(0, Math.min(currentIndex, tabs.count - 1));
        if (!tabs.count) {
            if (host) host.hide();
            else addTab();
        } else Qt.callLater(activate);
    }
    function restartShell() {
        const holder = sessions.itemAt(currentIndex);
        if (!holder) return;
        holder.restart();
    }
    function runCommand(command) {
        if (!currentTerminal) return;
        message = currentTerminal.runCommand(command);
    }
    function reloadCommands() {
        commandsLoading = true;
        commandsError = "";
        configWorker.request("config", {}, (result, error) => {
            commandsLoading = false;
            commandsError = error;
            commands = error ? [] : result.commands;
        });
    }
    function openCommands() { commandsPopup.open(); }
    function closeCommands() { commandsPopup.close(); }
    onVisibleChanged: if (!visible) closeCommands()

    ListModel { id: tabs }
    Shortcut { enabled: root.visible && tabs.count > 0; sequence: "Ctrl+Shift+T"; onActivated: root.addTab() }
    Shortcut { enabled: root.visible && tabs.count > 0; sequence: "Ctrl+Shift+W"; onActivated: root.closeTab(root.currentIndex) }
    Shortcut { enabled: root.visible && tabs.count > 0; sequence: "Ctrl+Tab"; onActivated: root.selectTab((root.currentIndex + 1) % tabs.count) }
    Shortcut { enabled: root.visible && tabs.count > 0; sequence: "Ctrl+Shift+Tab"; onActivated: root.selectTab((root.currentIndex + tabs.count - 1) % tabs.count) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconButton {
                objectName: "terminalNewTab"
                iconName: "plus"; text: "New terminal tab"
                onClicked: root.addTab()
            }
            Flickable {
                id: tabStrip
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                contentWidth: tabRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                function revealCurrent() {
                    const tab = tabButtons.itemAt(root.currentIndex);
                    if (!tab) return;
                    if (tab.x < contentX) contentX = tab.x;
                    else if (tab.x + tab.width > contentX + width) contentX = tab.x + tab.width - width;
                }
                Connections {
                    target: root
                    function onCurrentIndexChanged() { Qt.callLater(tabStrip.revealCurrent); }
                }
                Row {
                    id: tabRow
                    spacing: 4
                    Repeater {
                        id: tabButtons
                        model: tabs
                        delegate: RowLayout {
                            required property int index
                            required property int number
                            spacing: 0
                            Action {
                                Layout.preferredWidth: 154
                                text: {
                                    root.sessionsRevision;
                                    const session = sessions.itemAt(parent.index);
                                    return session && session.view && session.view.title ? session.view.title : "Shell " + parent.number;
                                }
                                highlighted: root.currentIndex === parent.index
                                textAlignment: Text.AlignLeft
                                onClicked: root.selectTab(parent.index)
                            }
                            IconButton {
                                Layout.preferredWidth: 32
                                iconSize: 16
                                iconName: "x"; text: "Close tab"
                                onClicked: root.closeTab(parent.index)
                            }
                        }
                    }
                }
            }
            IconButton {
                iconName: "copy"; text: "Copy selection"
                enabled: !!root.currentTerminal
                onClicked: root.currentTerminal.copySelection()
            }
            IconButton {
                iconName: "file-text"; text: "Paste from clipboard"
                enabled: !!root.currentTerminal
                onClicked: { root.currentTerminal.pasteClipboard(); root.activate(); }
            }
            IconButton {
                iconName: "rotate-ccw"; text: "Restart shell in this tab"
                onClicked: root.restartShell()
            }
            IconButton {
                id: commandsButton
                objectName: "terminalCommands"
                iconName: "play"; text: "Commands"
                onClicked: root.openCommands()
            }
        }
        Label {
            Layout.fillWidth: true
            visible: !!root.message
            text: root.message
            color: Theme.warning
            wrapMode: Text.WordWrap
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background
            radius: Theme.radius
            border.color: Theme.border
            border.width: 1
            Repeater {
                id: sessions
                model: tabs
                onItemAdded: root.sessionsRevision++
                onItemRemoved: root.sessionsRevision++
                delegate: Item {
                    id: holder
                    required property int index
                    required property int number
                    property alias view: terminalLoader.item
                    anchors.fill: parent
                    anchors.margins: 10
                    visible: root.currentIndex === index
                    function restart() { terminalLoader.active = false; restartTimer.restart(); }
                    Loader {
                        id: terminalLoader
                        anchors.fill: parent
                        asynchronous: true
                        source: "TerminalView.qml"
                        onStatusChanged: root.sessionsRevision++
                        onLoaded: {
                            root.sessionsRevision++;
                            if (holder.index === root.currentIndex) Qt.callLater(root.activate);
                        }
                    }
                    Timer { id: restartTimer; interval: 1; onTriggered: terminalLoader.active = true }
                    Connections {
                        target: terminalLoader.item
                        function onFinished() {
                            const number = holder.number;
                            Qt.callLater(() => {
                                for (let index = 0; index < tabs.count; ++index)
                                    if (tabs.get(index).number === number) { root.closeTab(index); break; }
                            });
                        }
                    }
                    BusySpinner { anchors.centerIn: parent; running: terminalLoader.status === Loader.Loading; visible: running }
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: terminalLoader.status === Loader.Error
                        Label { text: "The embedded terminal is unavailable."; color: Theme.muted }
                        Action {
                            text: "Open system terminal"; iconName: "terminal"
                            onClicked: fallback.request("terminal", {}, (result, error) => {
                                root.message = error || "";
                                if (!error && root.host) root.host.hide();
                            })
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: commandsPopup
        objectName: "terminalCommandsPopup"
        parent: root
        popupType: Popup.Item
        x: Math.max(0, root.width - width)
        y: commandsButton.height + 4
        width: Math.min(root.width, 380)
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: root.reloadCommands()
        background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border }
        contentItem: ColumnLayout {
            spacing: 8
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(commandList.implicitHeight, 360)
                clip: true
                Column {
                    id: commandList
                    width: parent.width
                    Repeater {
                        model: root.commandsLoading ? [] : root.commands
                        delegate: Action {
                            objectName: "terminalSavedCommand"
                            required property var modelData
                            width: commandList.width
                            iconName: "play"
                            text: modelData.name
                            textAlignment: Text.AlignLeft
                            enabled: !!root.currentTerminal
                            onClicked: { commandsPopup.close(); root.runCommand(modelData.command); }
                        }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                visible: root.commandsLoading || !!root.commandsError || !root.commands.length
                text: root.commandsLoading ? "Loading commands…" : root.commandsError || "Add named commands to the configuration below."
                color: root.commandsError ? Theme.danger : Theme.muted
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            Action {
                Layout.fillWidth: true
                iconName: "file-text"; text: "Open commands configuration"
                textAlignment: Text.AlignLeft
                enabled: !root.commandsLoading
                onClicked: {
                    commandsPopup.close();
                    fallback.request("open", {path: root.configPath}, (result, error) => { root.message = error; });
                }
            }
            Label {
                Layout.fillWidth: true
                text: root.configPath
                color: Theme.muted
                font.pixelSize: Theme.sp(12)
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideNone
            }
        }
    }
    FilesService { id: fallback }
    Worker {
        id: configWorker
        backend: "plugins/terminal/backend.py"
        serviceName: "Terminal commands"
        onReady: root.reloadCommands()
    }
    Component.onCompleted: addTab()
}
