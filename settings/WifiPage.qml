import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    spacing: 14
    property var selected: null
    property string error: ""
    property bool passwordNeeded: false
    readonly property var devices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var networks: devices.reduce((all, device) => all.concat(device.networks.values), []).filter(network => network.name).sort((a, b) => Number(b.connected) - Number(a.connected) || b.signalStrength - a.signalStrength)
    readonly property bool supportsPassword: selected && [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(selected.security)
    Repeater {
        model: root.devices
        delegate: Item {
            required property var modelData
            property bool previous: false
            Component.onCompleted: { previous = modelData.scannerEnabled; modelData.scannerEnabled = true; }
            Component.onDestruction: if (modelData) modelData.scannerEnabled = previous
        }
    }
    Action { text: Networking.wifiEnabled ? "Wi-Fi on · Turn off" : "Turn on Wi-Fi"; Layout.fillWidth: true; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
    Label { text: "Available networks"; color: Theme.muted }
    ListView {
        id: list
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
        model: Networking.wifiEnabled ? root.networks : []
        delegate: Action {
            required property var modelData
            width: ListView.view.width; implicitHeight: 52
            text: (modelData.connected ? "✓   " : "") + modelData.name + "   ·   " + Math.round(modelData.signalStrength * 100) + "%"
            highlighted: root.selected === modelData
            onClicked: { root.selected = modelData; root.error = ""; root.passwordNeeded = !modelData.known && root.supportsPassword; password.text = ""; }
        }
        WheelScroll { view: list }
        ScrollBar.vertical: ScrollBar {}
    }
    Label { visible: Networking.wifiEnabled && !root.networks.length; text: "Searching for networks…"; color: Theme.muted }
    ColumnLayout {
        visible: !!root.selected; Layout.fillWidth: true; spacing: 10
        Label { text: root.selected ? root.selected.name + " · " + WifiSecurityType.toString(root.selected.security) : ""; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SearchField { id: password; visible: root.passwordNeeded; Layout.fillWidth: true; placeholderText: "Network password"; echoMode: TextInput.Password; onAccepted: root.connectSelected() }
        Label { text: root.error; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.danger }
        RowLayout {
            Action {
                Layout.fillWidth: true
                text: root.selected && root.selected.stateChanging ? "Connecting…" : root.selected && root.selected.connected ? "Disconnect" : "Connect"
                enabled: root.selected && !root.selected.stateChanging && (!root.passwordNeeded || password.text.length > 0)
                onClicked: { if (root.selected.connected) root.selected.disconnect(); else root.connectSelected(); }
            }
            Action { text: "Cancel"; onClicked: { root.selected = null; password.text = ""; } }
        }
    }
    Connections {
        target: root.selected
        function onConnectionFailed(reason) {
            root.error = "Could not connect: " + ConnectionFailReason.toString(reason);
            if (root.supportsPassword) root.passwordNeeded = true;
        }
        function onConnectedChanged() { if (root.selected && root.selected.connected) { password.text = ""; root.passwordNeeded = false; root.error = ""; } }
    }
    function connectSelected() {
        if (!selected) return;
        error = "";
        if (passwordNeeded && supportsPassword) { selected.connectWithPsk(password.text); password.text = ""; }
        else if (selected.known || [WifiSecurityType.Open, WifiSecurityType.Owe].includes(selected.security)) selected.connect();
        else if (supportsPassword) passwordNeeded = true;
        else error = "This network needs an existing enterprise profile. Certificate and enterprise setup are not supported here yet.";
    }
}
