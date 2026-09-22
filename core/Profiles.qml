pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower

QtObject {
    id: root
    property var data: ({profiles: [], battery: {}, active: ""})
    property string error: ""
    property bool loaded: false
    property bool applying: false
    property bool pendingAutomatic: false
    property bool startup: true
    property var queue: []
    property string operation: "get"
    readonly property bool busy: process.running || queue.length > 0
    readonly property var names: data.profiles.map(p => p.name)
    readonly property var battery: UPower.displayDevice
    readonly property string batteryState: !battery || !battery.isPresent ? "default" : UPower.onBattery ? (battery.percentage * 100 <= (data.lowBatteryPercent || 20) ? "low" : "discharging") : "default"
    onBatteryStateChanged: if (loaded) automatic()
    function automatic(force) {
        if (busy) { pendingAutomatic = true; return; }
        pendingAutomatic = false;
        const name = data.battery[batteryState];
        if (name && (force || name !== data.active)) select(name);
    }
    function send(operation, value) { queue = queue.concat([{operation: operation, value: value || ""}]); next(); }
    function next() {
        if (process.running || queue.length === 0) return;
        const task = queue[0]; queue = queue.slice(1); operation = task.operation;
        process.command = ["python3", Paths.file("scripts/profiles.py"), task.operation, task.value]; process.running = true;
    }
    function select(name) { if (!busy) { applying = true; send("select", name); } }
    function edit(key, value) { if (!loaded || applying) return; const change = {}; change[key] = value; send("edit", JSON.stringify(change)); }
    function assign(state, name) { const change = {}; change[state] = name; send("battery", JSON.stringify(change)); }
    property Connections wifiChanges: Connections { target: Networking; function onWifiEnabledChanged() { root.edit("wifi", Networking.wifiEnabled); } }
    property Connections bluetoothChanges: Connections { target: Bluetooth.defaultAdapter; function onEnabledChanged() { if (Bluetooth.defaultAdapter) root.edit("bluetooth", Bluetooth.defaultAdapter.enabled); } }
    property Process process: Process {
        command: ["python3", Paths.file("scripts/profiles.py"), "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text); root.error = result.error || "";
                    if (result.data) {
                        root.data = result.data; root.loaded = true;
                        if (root.operation === "select") {
                            const settings = root.data.profiles.find(p => p.name === root.data.active).settings;
                            if (typeof settings.wifi === "boolean" && Networking.wifiHardwareEnabled) Networking.wifiEnabled = settings.wifi;
                            if (typeof settings.bluetooth === "boolean" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = settings.bluetooth;
                        }
                    }
                } catch (e) { root.error = "Could not load profiles: " + e; }
            }
        }
        onExited: { settle.restart(); Qt.callLater(root.next); }
    }
    property Timer settle: Timer { interval: 600; onTriggered: { root.applying = false; if (root.startup || root.pendingAutomatic) { const first = root.startup; root.startup = false; root.automatic(first); } } }
}
