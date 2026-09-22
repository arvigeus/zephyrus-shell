import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    spacing: 14
    property var adapter: Bluetooth.defaultAdapter
    property var selected: null
    property var pairingDevice: null
    property var prompt: ({})
    property string error: ""
    property bool confirmForget: false
    property bool scanning: false
    property bool ownsDiscovery: false
    function scan() { if (adapter && adapter.enabled) { ownsDiscovery = !adapter.discovering; if (ownsDiscovery) adapter.discovering = true; scanning = true; scanTimeout.restart(); } }
    function stopScan() { if (ownsDiscovery && adapter) adapter.discovering = false; ownsDiscovery = false; scanning = false; }
    Component.onDestruction: { stopScan(); if (pairingDevice && pairingDevice.pairing) pairingDevice.cancelPair(); }
    Timer { id: scanTimeout; interval: 30000; onTriggered: root.stopScan() }
    Choice {
        visible: Bluetooth.adapters.values.length > 1
        Layout.fillWidth: true; model: Bluetooth.adapters.values; textRole: "name"
        displayText: root.adapter ? root.adapter.name : "No adapter"
        enabled: !pairing.running
        onActivated: index => { root.stopScan(); root.adapter = model[index]; }
    }
    RowLayout {
        Layout.fillWidth: true
        Action { text: root.adapter && root.adapter.enabled ? "Bluetooth on" : "Turn on Bluetooth"; enabled: !!root.adapter; Layout.fillWidth: true; onClicked: root.adapter.enabled = !root.adapter.enabled }
        Action { text: root.scanning ? "Stop scan" : "Find devices"; enabled: !!root.adapter && root.adapter.enabled; onClicked: root.scanning ? root.stopScan() : root.scan() }
    }
    ListView {
        id: list
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
        model: root.adapter ? root.adapter.devices.values.slice().sort((a,b) => Number(b.connected) - Number(a.connected) || Number(b.paired) - Number(a.paired) || a.name.localeCompare(b.name)) : []
        delegate: Action {
            required property var modelData
            width: ListView.view.width; implicitHeight: 52
            text: modelData.name + " · " + (modelData.connected ? "Connected" : modelData.paired ? "Paired" : "New")
            highlighted: root.selected === modelData
            enabled: !pairing.running
            onClicked: { root.selected = modelData; root.confirmForget = false; root.error = ""; }
        }
        WheelScroll { view: list }
        ScrollBar.vertical: ScrollBar {}
    }
    Label { visible: list.count === 0; text: root.scanning ? "Searching for nearby devices…" : "Choose Find devices to discover nearby devices."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Label { visible: !!root.selected; text: root.selected ? root.selected.name + " · " + BluetoothDeviceState.toString(root.selected.state) : ""; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Label { visible: pairing.running; text: root.prompt.code ? (root.prompt.kind === "display" ? "Enter this code on the device: " : "Confirm the code matches: ") + root.prompt.code : "Pairing…"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.accent }
    SearchField { id: pin; visible: ["pin", "passkey"].includes(root.prompt.kind); placeholderText: "PIN / passkey"; Layout.fillWidth: true }
    RowLayout {
        visible: ["confirm", "pin", "passkey"].includes(root.prompt.kind)
        Action { text: "Confirm"; onClicked: root.answer(true) }
        Action { text: "Decline"; onClicked: root.answer(false) }
    }
    Label { text: root.error; visible: text !== ""; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        visible: !!root.selected; Layout.fillWidth: true
        Action {
            Layout.fillWidth: true
            text: pairing.running ? "Cancel pairing" : root.selected && root.selected.connected ? "Disconnect" : root.selected && root.selected.paired ? "Connect" : "Pair & connect"
            onClicked: {
                root.error = "";
                if (pairing.running) { if (root.pairingDevice) root.pairingDevice.cancelPair(); pairing.running = false; root.prompt = {}; }
                else if (root.selected.connected) root.selected.disconnect();
                else if (root.selected.paired) root.selected.connect();
                else { root.pairingDevice = root.selected; root.prompt = {}; pairing.command = ["python3", Paths.file("scripts/bluetooth_pair.py"), root.selected.dbusPath]; pairing.running = true; }
            }
        }
        Action { text: root.confirmForget ? "Confirm forget" : "Forget"; visible: root.selected && root.selected.paired; enabled: !pairing.running; onClicked: { if (root.confirmForget) { root.selected.forget(); root.selected = null; } else root.confirmForget = true; } }
    }
    Process {
        id: pairing
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    if (event.kind === "error") { root.error = event.message; root.prompt = {}; }
                    else if (event.kind === "paired") { root.prompt = {}; if (root.pairingDevice) root.pairingDevice.connect(); }
                    else root.prompt = event;
                } catch (error) { root.error = "Could not read pairing response."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = "Pairing helper failed. Check that python-dbus and python-gobject are installed." }
    }
    function answer(accept) { pairing.write(JSON.stringify({accept: accept, value: pin.text}) + "\n"); pin.text = ""; prompt = {}; }
}
