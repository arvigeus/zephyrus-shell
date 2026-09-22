pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property var data: ({})
    property string error: ""
    readonly property bool busy: query.running
    function refresh() { if (!busy) { error = ""; query.running = true; } }
    property Process query: Process {
        command: ["python3", Paths.file("scripts/machine.py"), "snapshot"]
        running: true
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim(); }
        stdout: StdioCollector {
            onStreamFinished: {
                try { const result = JSON.parse(text); if (result.error) root.error = result.error; else root.data = result; }
                catch (error) { root.error = "Could not read machine status: " + error; }
            }
        }
    }
}
