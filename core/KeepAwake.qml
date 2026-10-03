pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property string mode: "off"
    property bool sleepActive: false
    property bool screenActive: false
    readonly property bool active: mode === "sleep" ? sleepActive : mode === "screen" ? screenActive : false
    property string error: ""

    function setMode(next) {
        if (!["off", "sleep", "screen"].includes(next) || mode === next) return;
        error = "";
        mode = next;
        sleepLock.running = next === "sleep";
        screenLock.running = next === "screen";
        if (next !== "off") wakeDisplays.running = true;
    }

    property Process wakeDisplays: Process {
        command: ["python3", Paths.file("scripts/machine.py"), "wake-displays"]
    }
    function lockStopped(kind) {
        if (mode !== kind) return;
        mode = "off";
        if (!error) error = "Could not keep the system awake.";
    }

    property Process sleepLock: Process {
        command: ["systemd-inhibit", "--what=sleep", "--mode=block",
                  "--who=Zephyrus Shell", "--why=Automatic sleep is disabled in Settings",
                  "sleep", "infinity"]
        stderr: StdioCollector { onStreamFinished: if (root.mode === "sleep" && text.trim()) root.error = text.trim() }
        onStarted: root.sleepActive = true
        onExited: (exitCode, exitStatus) => { root.sleepActive = false; root.lockStopped("sleep"); }
        onRunningChanged: if (!running && root.mode === "sleep") Qt.callLater(() => {
            if (!sleepLock.running) root.lockStopped("sleep");
        })
    }
    property Process screenLock: Process {
        command: ["systemd-inhibit", "--what=idle:sleep", "--mode=block",
                  "--who=Zephyrus Shell", "--why=Keep screen on is enabled in Settings",
                  "sleep", "infinity"]
        stderr: StdioCollector { onStreamFinished: if (root.mode === "screen" && text.trim()) root.error = text.trim() }
        onStarted: root.screenActive = true
        onExited: (exitCode, exitStatus) => { root.screenActive = false; root.lockStopped("screen"); }
        onRunningChanged: if (!running && root.mode === "screen") Qt.callLater(() => {
            if (!screenLock.running) root.lockStopped("screen");
        })
    }
}
