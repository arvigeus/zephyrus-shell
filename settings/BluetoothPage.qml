import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"
import "../widgets"
import "DeviceIcons.js" as DeviceIcons

ColumnLayout {
    id: root
    spacing: 8
    property var adapter: Bluetooth.defaultAdapter
    property bool compact: false
    property var selected: null
    property var pairingDevice: null
    property var forgetCandidate: null
    property var prompt: ({})
    property string pinValue: ""
    property string error: ""
    property bool scanning: false
    property bool ownsDiscovery: false
    onVisibleChanged: if (!visible) stopScan()

    function scan() {
        if (adapter && adapter.enabled) {
            ownsDiscovery = !adapter.discovering;
            if (ownsDiscovery) adapter.discovering = true;
            scanning = true;
            scanTimeout.restart();
        }
    }
    function stopScan() {
        if (ownsDiscovery && adapter) adapter.discovering = false;
        ownsDiscovery = false;
        scanning = false;
    }
    function toggle(device) {
        selected = device;
        error = "";
        forgetCandidate = null;
        if (pairing.running) {
            if (pairingDevice === device) {
                device.cancelPair();
                pairing.running = false;
                pairingDevice = null;
                prompt = {};
            }
        } else if (device.connected) device.disconnect();
        else if (device.paired) device.connect();
        else {
            pairingDevice = device;
            prompt = {};
            pairing.command = ["python3", Paths.file("scripts/bluetooth_pair.py"), device.dbusPath];
            pairing.running = true;
        }
    }
    function forget(device) {
        selected = device;
        if (forgetCandidate === device) {
            forgetTimeout.stop();
            device.forget();
            forgetCandidate = null;
            selected = null;
        } else {
            forgetCandidate = device;
            forgetTimeout.restart();
        }
    }
    function answer(accept) {
        pairing.write(JSON.stringify({accept: accept, value: pinValue}) + "\n");
        pinValue = "";
        prompt = {};
    }

    Component.onDestruction: { stopScan(); if (pairingDevice && pairingDevice.pairing) pairingDevice.cancelPair(); }
    Timer { id: scanTimeout; interval: 30000; onTriggered: root.stopScan() }
    Timer { id: forgetTimeout; interval: 5000; onTriggered: root.forgetCandidate = null }
    Choice {
        visible: Bluetooth.adapters.values.length > 1
        Layout.fillWidth: true; model: Bluetooth.adapters.values; textRole: "name"
        displayText: root.adapter ? root.adapter.name : "No adapter"
        enabled: !pairing.running
        onActivated: index => { root.stopScan(); root.adapter = model[index]; }
    }
    RowLayout {
        Layout.fillWidth: true
        Action { visible: !root.compact; text: root.adapter && root.adapter.enabled ? "Bluetooth on" : "Turn on Bluetooth"; enabled: !!root.adapter; Layout.fillWidth: true; onClicked: root.adapter.enabled = !root.adapter.enabled }
        Action { text: root.scanning ? "Stop scan" : "Find devices"; iconName: root.scanning ? "x" : "search"; enabled: !!root.adapter && root.adapter.enabled; Layout.fillWidth: root.compact; onClicked: root.scanning ? root.stopScan() : root.scan() }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: !root.compact
        Layout.preferredHeight: root.compact ? Math.min(contentHeight, 240) : -1
        clip: true
        spacing: 4
        model: root.adapter ? root.adapter.devices.values.slice().sort((a, b) => Number(b.paired) - Number(a.paired) || a.name.localeCompare(b.name)) : []
        delegate: Item {
            required property var modelData
            width: ListView.view.width
            height: entry.implicitHeight + 4
            ColumnLayout {
                id: entry
                width: parent.width
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Icon { name: DeviceIcons.icon(modelData.icon); Layout.preferredWidth: 22; Layout.preferredHeight: 22; opacity: modelData.connected ? 1 : 0.5 }
                    Action {
                        Layout.fillWidth: true
                        text: modelData.name
                        textAlignment: Text.AlignLeft
                        highlighted: root.selected === modelData && modelData.connected
                        onClicked: { root.selected = modelData; root.forgetCandidate = null; root.error = ""; }
                        contentItem: Label { text: modelData.name; color: modelData.connected ? Theme.text : Theme.muted; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                    }
                    Icon { name: "check"; visible: modelData.paired; Layout.preferredWidth: 18; Layout.preferredHeight: 18; opacity: 0.7; Accessible.name: "Paired" }
                    IconButton {
                        iconName: modelData.pairing ? "refresh-cw" : modelData.connected ? "link" : "link-2-off"
                        iconSize: 17
                        Layout.preferredWidth: 36
                        text: pairing.running && root.pairingDevice === modelData ? "Cancel pairing with " + modelData.name : modelData.connected ? "Disconnect " + modelData.name : modelData.paired ? "Connect " + modelData.name : "Pair and connect " + modelData.name
                        enabled: !!root.adapter && root.adapter.enabled && (!pairing.running || root.pairingDevice === modelData)
                        opacity: modelData.connected ? 1 : 0.65
                        onClicked: root.toggle(modelData)
                    }
                    IconButton {
                        visible: modelData.paired
                        iconName: "trash-2"
                        iconSize: 17
                        Layout.preferredWidth: 36
                        text: root.forgetCandidate === modelData ? "Confirm forget " + modelData.name : "Forget " + modelData.name
                        highlighted: root.forgetCandidate === modelData
                        opacity: root.forgetCandidate === modelData ? 1 : 0.5
                        enabled: !pairing.running
                        onClicked: root.forget(modelData)
                    }
                }
                ColumnLayout {
                    visible: root.selected === modelData && (root.forgetCandidate === modelData || modelData.batteryAvailable || pairing.running && root.pairingDevice === modelData || root.error !== "")
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    spacing: 6
                    Label { visible: root.forgetCandidate === modelData; text: "Press forget again to remove this device"; color: Theme.danger; font.pixelSize: 11 }
                    Label { visible: modelData.batteryAvailable; text: "Battery " + Math.round(modelData.battery * 100) + "%"; color: Theme.muted; font.pixelSize: 11 }
                    Label {
                        visible: pairing.running && root.pairingDevice === modelData
                        text: root.prompt.code ? (root.prompt.kind === "display" ? "Enter this code on the device: " : "Confirm the code matches: ") + root.prompt.code : "Pairing…"
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.accent
                    }
                    SearchField {
                        visible: ["pin", "passkey"].includes(root.prompt.kind) && root.pairingDevice === modelData
                        placeholderText: "PIN / passkey"
                        Layout.fillWidth: true
                        text: root.pinValue
                        onTextChanged: root.pinValue = text
                        onAccepted: root.answer(true)
                    }
                    RowLayout {
                        visible: ["confirm", "pin", "passkey"].includes(root.prompt.kind) && root.pairingDevice === modelData
                        Action { text: "Confirm"; onClicked: root.answer(true) }
                        Action { text: "Decline"; onClicked: root.answer(false) }
                    }
                    Label { text: root.error; visible: text !== ""; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
        }
        WheelScroll { view: list }
        ScrollBar.vertical: ScrollBar {}
    }
    Label { visible: list.count === 0; text: root.scanning ? "Searching for nearby devices…" : "Choose Find devices to discover nearby devices."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
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
        onExited: root.pairingDevice = null
    }
}
