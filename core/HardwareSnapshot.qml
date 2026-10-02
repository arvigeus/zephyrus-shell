pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

QtObject {
    id: root
    property var data: ({})
    property var homeUsage: null
    property string error: ""
    property double checkedAt: 0
    property int generation: 0
    property int queryGeneration: 0
    property bool refreshPending: false
    property bool forceDdcPending: false
    readonly property bool busy: query.running
    function ensureFresh() { if (Date.now() - checkedAt >= 30000) refresh(); }
    function invalidate() { generation++; checkedAt = 0; }
    function requestRefresh() { events.restart(); }
    function refresh(forceDdc) {
        if (busy) { refreshPending = true; forceDdcPending = forceDdcPending || !!forceDdc; return; }
        error = ""; queryGeneration = generation;
        query.command = ["python3", Paths.file("scripts/machine.py"), "snapshot", forceDdc ? "refresh" : ""];
        query.running = true;
    }
    property Timer events: Timer { interval: 300; onTriggered: root.refresh() }
    property Connections profileChanges: Connections { target: Profiles; function onBusyChanged() { if (!Profiles.busy) root.requestRefresh(); } }
    property Connections batteryChanges: Connections { target: UPower.displayDevice; function onStateChanged() { root.requestRefresh(); } }
    property Connections powerSourceChanges: Connections { target: UPower; function onOnBatteryChanged() { root.requestRefresh(); } }
    property Connections monitorChanges: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name)) displayEvents.restart();
        }
    }
    property Timer displayEvents: Timer { interval: 350; onTriggered: {
        if (displayRecovery.running) root.recoveryPending = true;
        else displayRecovery.running = true;
    } }
    property bool recoveryPending: false
    property Process displayRecovery: Process {
        command: ["python3", Paths.file("scripts/machine.py"), "recover-displays"]
        running: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
        stdout: StdioCollector { onStreamFinished: {
            try { const result = JSON.parse(text); if (result.error) root.error = result.error; }
            catch (error) { root.error = "Could not recover displays: " + error; }
        } }
        onExited: {
            root.requestRefresh();
            if (root.recoveryPending) { root.recoveryPending = false; displayEvents.restart(); }
        }
    }
    property Process query: Process {
        command: ["python3", Paths.file("scripts/machine.py"), "snapshot"]
        running: true
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim(); }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.queryGeneration !== root.generation) return;
                try { const result = JSON.parse(text); if (result.error) root.error = result.error; else root.data = result; }
                catch (error) { root.error = "Could not read machine status: " + error; }
                root.checkedAt = Date.now();
            }
        }
        onExited: if (root.refreshPending) {
            const force = root.forceDdcPending;
            root.refreshPending = false; root.forceDdcPending = false;
            Qt.callLater(() => root.refresh(force));
        }
    }
}
