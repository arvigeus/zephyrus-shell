import QtQuick
import Quickshell.Io
import "../core"

// Runs one allowlisted scripts/machine.py action at a time, then refreshes.
QtObject {
    id: root
    readonly property var snapshot: HardwareSnapshot.data
    property string actionError: ""
    readonly property string error: actionError || HardwareSnapshot.error
    property string actionName: ""
    property var actionValue
    property bool actionSucceeded: false
    readonly property bool busy: action.running
    function refresh() { if (!action.running) HardwareSnapshot.refresh(true); }
    Component.onCompleted: HardwareSnapshot.ensureFresh()
    function run(name, value) {
        if (busy) return;
        HardwareSnapshot.invalidate();
        actionError = "";
        actionName = name; actionValue = value; actionSucceeded = false;
        action.command = ["python3", Paths.file("scripts/machine.py"), name, String(value === undefined ? "" : value)];
        action.running = true;
    }
    property Process action: Process {
        stdout: StdioCollector {
            onStreamFinished: { try { const result = JSON.parse(text); root.actionError = result.error || ""; root.actionSucceeded = !!result.ok; } catch (error) { root.actionError = "Action did not return a result."; } }
        }
        onExited: {
            if (root.actionSucceeded && ["profile", "brightness", "chargeLimit"].includes(root.actionName)) Profiles.edit(root.actionName, root.actionValue);
            if (root.actionSucceeded && root.actionName === "clean-thumbnails") HardwareSnapshot.homeUsage = null;
            root.refresh();
        }
    }
}
