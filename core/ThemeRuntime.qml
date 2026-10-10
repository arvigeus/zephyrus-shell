pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "theme" as Design

QtObject {
    id: root
    readonly property string script: Paths.file("scripts/theme.py")
    property bool desktopSync: false
    property bool pending: false
    property bool syncPending: false
    readonly property bool busy: process.running || settingsProcess.running || modeProcess.running
    function setMode(mode) {
        if (busy) return;
        modeProcess.command = ["python3", script, "set-mode", mode];
        modeProcess.running = true;
    }
    property Process modeProcess: Process {
        stdout: StdioCollector { onStreamFinished: {
            try { Design.Theme.error = JSON.parse(text).error || ""; }
            catch (error) { Design.Theme.error = "Could not change theme: " + error; }
        } }
        onExited: root.refresh()
    }
    // Only the real shell calls start(). Importing Theme in a preview or test
    // reads settings without writing desktop configuration or sending D-Bus.
    function start() { desktopSync = true; refresh(); }
    function refresh() {
        if (settingsProcess.running) pending = true;
        else {
            pending = false;
            settingsProcess.command = ["python3", script, "get"];
            settingsProcess.running = true;
        }
        applyDesktopSync();
    }
    function applyDesktopSync() {
        if (!desktopSync) return;
        if (process.running) { syncPending = true; return; }
        syncPending = false;
        process.command = ["python3", script, "apply"];
        if (Quickshell.env("ZEPHYRUS_THEME_NO_NOTIFY") === "1") process.command = process.command.concat(["--no-notify"]);
        process.running = true;
    }
    function acceptSettings(text) {
        try {
            const result = JSON.parse(text);
            Design.Theme.error = result.error || "";
            if (result.theme) { Design.Theme.settings = result.theme; Design.Theme.loaded = true; }
            // Re-arm the watch: a file created after startup is otherwise missed.
            root.userFile.reload();
            if (Design.Theme.error) console.warn("Theme:", Design.Theme.error);
        } catch (exception) { Design.Theme.error = "Could not read theme settings: " + exception; }
    }
    property FileView defaultFile: FileView {
        path: Paths.file("config/theme.json")
        watchChanges: true
        onFileChanged: { reload(); debounce.restart(); }
    }
    property FileView userFile: FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zephyrus-shell/theme.json"
        printErrors: false
        watchChanges: true
        onFileChanged: { reload(); debounce.restart(); }
    }
    property Timer debounce: Timer { interval: 200; onTriggered: root.refresh() }
    property Process settingsProcess: Process {
        stdout: StdioCollector { onStreamFinished: root.acceptSettings(text) }
        onExited: if (root.pending) root.debounce.restart()
    }
    property Process process: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    Design.Theme.warnings = result.warnings || [];
                    if (result.error) {
                        Design.Theme.error = result.error;
                        console.warn("Theme:", Design.Theme.error);
                    }
                    for (const warning of Design.Theme.warnings) console.warn("Theme:", warning);
                } catch (exception) { console.warn("Theme sync:", exception); }
            }
        }
        onExited: if (root.syncPending) root.applyDesktopSync()
    }
    Component.onCompleted: debounce.restart()
    property Connections reloadRequests: Connections {
        target: Design.Theme
        function onReloadRequested() { root.refresh(); }
        function onModeRequested(mode) { root.setMode(mode); }
    }
}
