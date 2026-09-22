import QtQuick
import Quickshell.Io
import "../core"
import "AudioNames.js" as Names

QtObject {
    id: root
    property var snapshot: ({rules: [], devices: {}, errors: []})
    property string error: ""
    readonly property bool changingProfile: profileAction.running
    function describe(node) { return Names.describe(node, snapshot); }
    function refresh() { if (query.running) debounce.restart(); else query.running = true; }
    function enableInput(candidate) {
        if (profileAction.running) return;
        error = "";
        profileAction.command = ["python3", Paths.file("scripts/audio_devices.py"), "enable-input", candidate.card, candidate.profile, candidate.previous];
        profileAction.running = true;
    }
    property Process profileAction: Process {
        stdout: StdioCollector { onStreamFinished: { try { root.error = JSON.parse(text).error || ""; } catch (error) { root.error = "Could not change audio mode."; } } }
        onExited: root.refresh()
    }
    property Timer debounce: Timer { interval: 200; onTriggered: root.refresh() }
    property Process query: Process {
        command: ["python3", Paths.file("scripts/audio_devices.py"), Paths.file("config/audio")]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { root.snapshot = JSON.parse(text); } catch (error) { console.warn("Audio metadata:", error); } } }
    }
    property Process changes: Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser { onRead: line => { if (/ on (sink|source|card|server) #/.test(line)) root.debounce.restart(); } }
    }
}
