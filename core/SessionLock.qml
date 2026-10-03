pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool loaded: false
    property bool available: false
    property bool paused: false
    property string error: ""
    readonly property bool busy: process.running
    function refresh() { send("get"); }
    function setPaused(value) { if (available) send(value ? "pause" : "restore"); }
    function send(action) {
        if (busy) return;
        error = "";
        process.command = ["python3", Paths.file("scripts/idle.py"), action];
        process.running = true;
    }
    property Process process: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.available = !!result.available;
                    root.paused = !!result.paused;
                    root.error = result.error || "";
                    root.loaded = true;
                } catch (exception) { root.error = "Could not read automatic locking state."; }
            }
        }
    }
    Component.onCompleted: refresh()
}
