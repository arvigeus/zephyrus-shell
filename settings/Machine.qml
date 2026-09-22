import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../core"

QtObject {
    id: root
    readonly property var snapshot: HardwareSnapshot.data
    property string error: HardwareSnapshot.error
    property string actionName: ""
    property var actionValue
    property bool actionSucceeded: false
    property bool closeAfterAction: false
    readonly property bool busy: HardwareSnapshot.busy || action.running
    function refresh() { if (!action.running) HardwareSnapshot.refresh(); }
    Component.onCompleted: refresh()
    function run(name, value) {
        if (busy) return;
        error = "";
        actionName = name; actionValue = value; actionSucceeded = false;
        closeAfterAction = name === "networks" || name === "bluetooth";
        action.command = ["python3", Paths.file("scripts/machine.py"), name, String(value === undefined ? "" : value)];
        action.running = true;
    }
    property Connections profileChanges: Connections { target: Profiles; function onBusyChanged() { if (!Profiles.busy) root.refresh(); } }
    property Connections batteryChanges: Connections { target: UPower.displayDevice; function onPercentageChanged() { root.refresh(); } function onStateChanged() { root.refresh(); } }
    property Process action: Process {
        stdout: StdioCollector {
            onStreamFinished: { try { const result = JSON.parse(text); root.error = result.error || ""; root.actionSucceeded = !!result.ok; } catch (error) { root.error = "Action did not return a result."; } }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.actionSucceeded && ["profile", "brightness", "gpu", "chargeLimit"].includes(root.actionName)) Profiles.edit(root.actionName, root.actionValue);
            if (exitCode === 0 && root.closeAfterAction) ShellState.close();
            else root.refresh();
        }
    }
}
