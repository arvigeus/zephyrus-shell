pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var entries: []
    property var errors: []
    function reload() { if (!scan.running) scan.running = true; }
    function find(id) { return entries.find(entry => entry.id === id) || null; }
    property Process scan: Process {
        command: ["python3", Paths.file("scripts/plugins.py"), Paths.file("plugins")]
        running: true
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.errors = [text.trim()]; }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.entries = result.entries;
                    root.errors = result.errors;
                    if (ShellState.pluginId && !root.find(ShellState.pluginId)) ShellState.backToSpaces();
                }
                catch (error) { root.errors = ["Cannot read plugin registry: " + error]; }
            }
        }
    }
}
