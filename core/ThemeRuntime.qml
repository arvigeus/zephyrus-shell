pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "theme" as Design

QtObject {
    id: root
    readonly property string repository: decodeURIComponent(Qt.resolvedUrl("../").toString().replace(/^file:\/\//, "")).replace(/\/?$/, "/")
    readonly property string configDirectory: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    property bool desktopSync: false
    property bool pending: false
    property bool loaded: false
    readonly property bool busy: process.running || modeProcess.running
    function setMode(mode) {
        if (busy) return;
        modeProcess.command = ["python3", repository + "scripts/theme.py", "set-mode", mode];
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
        if (process.running) { pending = true; return; }
        pending = false;
        process.command = ["python3", repository + "scripts/theme.py", desktopSync ? "apply" : "get"];
        if (Quickshell.env("ZEPHYRUS_THEME_NO_NOTIFY") === "1") process.command = process.command.concat(["--no-notify"]);
        process.running = true;
    }
    property FileView defaultFile: FileView {
        path: root.repository + "config/theme.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: { reload(); debounce.restart(); }
    }
    property FileView userFile: FileView {
        path: root.configDirectory + "/zephyrus-shell/theme.json"
        printErrors: false
        watchChanges: true
        onFileChanged: { reload(); debounce.restart(); }
    }
    property Timer debounce: Timer { interval: 200; onTriggered: root.refresh() }
    property Process process: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    Design.Theme.error = result.error || "";
                    Design.Theme.warnings = result.warnings || [];
                    if (result.theme) { Design.Theme.settings = result.theme; Design.Theme.loaded = true; }
                    root.userFile.reload();
                    if (Design.Theme.error) console.warn("Theme:", Design.Theme.error);
                    for (const warning of Design.Theme.warnings) console.warn("Theme:", warning);
                } catch (exception) { Design.Theme.error = "Could not read theme settings: " + exception; }
            }
        }
        onExited: if (root.pending) debounce.restart()
    }
    Component.onCompleted: debounce.restart()
    property Connections reloadRequests: Connections {
        target: Design.Theme
        function onReloadRequested() { root.refresh(); }
        function onModeRequested(mode) { root.setMode(mode); }
    }
}
