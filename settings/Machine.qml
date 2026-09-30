import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

QtObject {
    id: root
    readonly property var snapshot: HardwareSnapshot.data
    property string actionError: ""
    readonly property string error: actionError || HardwareSnapshot.error
    property string actionName: ""
    property var actionValue
    property bool actionSucceeded: false
    property bool closeAfterAction: false
    readonly property bool busy: action.running
    function refresh() { if (!action.running) HardwareSnapshot.refresh(true); }
    Component.onCompleted: HardwareSnapshot.ensureFresh()
    function run(name, value) {
        if (busy) return;
        HardwareSnapshot.invalidate();
        actionError = "";
        actionName = name; actionValue = value; actionSucceeded = false;
        closeAfterAction = name === "networks" || name === "bluetooth";
        action.command = ["python3", Paths.file("scripts/machine.py"), name, String(value === undefined ? "" : value)];
        action.running = true;
    }
    property Process action: Process {
        stdout: StdioCollector {
            onStreamFinished: { try { const result = JSON.parse(text); root.actionError = result.error || ""; root.actionSucceeded = !!result.ok; } catch (error) { root.actionError = "Action did not return a result."; } }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.actionSucceeded && ["profile", "brightness", "gpu", "chargeLimit"].includes(root.actionName)) Profiles.edit(root.actionName, root.actionValue);
            if (root.actionSucceeded && root.actionName === "clean-thumbnails") HardwareSnapshot.homeUsage = null;
            if (exitCode === 0 && root.closeAfterAction) ShellState.close();
            else root.refresh();
        }
    }
}
