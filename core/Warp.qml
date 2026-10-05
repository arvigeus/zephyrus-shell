pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    readonly property string artwork: "data:image/svg+xml;charset=utf-8," + encodeURIComponent(logo.text().replace(/#ffffff/gi, Theme.text.toString()))
    property FileView logo: FileView { path: Paths.file("assets/brands/cloudflare.svg"); blockLoading: true }
    property bool available: false
    property bool enabled: false
    property string state: "off"
    property string message: ""
    property string error: ""
    property string pendingAction: "status"
    property string queuedAction: ""
    property bool requestActive: false
    readonly property bool busy: requestActive && pendingAction !== "status"
    readonly property bool transitioning: busy || state === "connecting" || state === "disconnecting"
    readonly property string label: busy ? (pendingAction === "disconnect" ? "Disconnecting…" : "Connecting…")
        : state === "connected" ? "Connected"
        : state === "connecting" ? "Connecting…"
        : state === "disconnecting" ? "Disconnecting…"
        : enabled ? "Disconnected · retrying" : state === "off" ? "" : "Unavailable"

    function apply(result) {
        if (result.available !== undefined) available = !!result.available;
        if (result.enabled !== undefined) enabled = !!result.enabled;
        if (result.state) state = result.state;
        if (result.message !== undefined) message = result.message;
        if (!result.ok) error = result.error || "WARP action failed.";
    }
    function refresh() { run("status"); }
    function toggle() { run(enabled ? "disconnect" : "connect"); }
    function run(action) {
        if (requestActive) {
            if (action !== "status" && pendingAction === "status") queuedAction = action;
            return;
        }
        pendingAction = action;
        if (action !== "status") error = "";
        process.command = ["python3", Paths.file("scripts/warp.py"), action, "--json"];
        requestActive = true;
        process.running = true;
    }
    property Process observer: Process {
        command: ["python3", Paths.file("scripts/warp.py"), "watch"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try { root.apply(JSON.parse(line)); }
                catch (error) { root.error = "Could not read WARP status."; }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) root.error = "WARP status listener failed: " + text.trim();
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode && !root.error) root.error = "WARP status listener stopped.";
        }
    }
    property Process process: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.ok) root.error = result.error || "WARP action failed.";
                    // The event stream owns status. An action's snapshot can be
                    // older than an event already received while it was running.
                    else if (!root.observer.running) root.apply(result);
                } catch (error) { root.error = "WARP did not return a result."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode && !root.error) root.error = "Could not control WARP.";
            root.requestActive = false;
            Qt.callLater(() => {
                if (root.queuedAction) {
                    const action = root.queuedAction;
                    root.queuedAction = "";
                    root.run(action);
                }
            });
        }
    }
}
