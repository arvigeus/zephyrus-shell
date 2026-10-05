import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../core"
import "../core/StatusIcons.js" as StatusIcons
import "../widgets"

ColumnLayout {
    id: root
    spacing: 8
    property var selected: null
    property bool compact: false
    property string error: ""
    property string password: ""
    property bool passwordNeeded: false
    readonly property var devices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var networks: devices.reduce((all, device) => all.concat(device.networks.values), []).filter(network => network.name).sort((a, b) => Number(b.known) - Number(a.known) || a.name.localeCompare(b.name))
    readonly property bool supportsPassword: selected && [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(selected.security)

    function isProtected(network) {
        return network && ![WifiSecurityType.Open, WifiSecurityType.Owe, WifiSecurityType.Unknown].includes(network.security);
    }
    function signalIcon(network) {
        return StatusIcons.wifiIcon(network.signalStrength, isProtected(network));
    }
    function networkDetails(network) {
        const status = network.stateChanging ? (network.state === ConnectionState.Disconnecting ? "Disconnecting" : "Connecting") : network.connected ? "Connected" : network.known ? "Saved" : "Available";
        const quality = Math.round((Number(network.signalStrength) || 0) * 100);
        const security = WifiSecurityType.toString(network.security);
        return network.name + "\n" + status + " · " + quality + "% signal\nSecurity: " + security;
    }

    function choose(network) {
        selected = network;
        error = "";
        password = "";
        passwordNeeded = !network.known && [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security);
    }
    function toggle(network) {
        if (network.stateChanging) return;
        if (network === selected && passwordNeeded && !network.connected) return;
        choose(network);
        if (network.connected) network.device.disconnect();
        else connectSelected();
    }
    function connectSelected() {
        if (!selected || selected.stateChanging) return;
        error = "";
        if (passwordNeeded && supportsPassword) {
            if (!password.length) return;
            selected.connectWithPsk(password);
            password = "";
        } else if (selected.known || [WifiSecurityType.Open, WifiSecurityType.Owe].includes(selected.security)) selected.connect();
        else if (supportsPassword) passwordNeeded = true;
        else error = "This network needs an existing enterprise profile. Certificate and enterprise setup are not supported here yet.";
    }

    Repeater {
        model: root.devices
        delegate: Item {
            id: scanner
            required property var modelData
            property bool previous: false
            property bool ready: false
            Component.onCompleted: { previous = modelData.scannerEnabled; ready = true; modelData.scannerEnabled = root.visible; }
            Connections { target: root; function onVisibleChanged() { if (scanner.ready) scanner.modelData.scannerEnabled = root.visible ? true : scanner.previous; } }
            Component.onDestruction: if (modelData) modelData.scannerEnabled = previous
        }
    }
    Action { visible: !root.compact; text: Networking.wifiEnabled ? "Wi-Fi on · Turn off" : "Turn on Wi-Fi"; Layout.fillWidth: true; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
    Label { visible: !root.compact; text: "Available networks"; color: Theme.muted }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: !root.compact
        Layout.preferredHeight: root.compact ? Math.min(contentHeight, 260) : -1
        clip: true
        spacing: 4
        model: Networking.wifiEnabled ? root.networks : []
        header: WarpNetworkRow { width: ListView.view.width }
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
                    IconButton {
                        iconName: modelData.stateChanging ? "wifi-sync" : root.signalIcon(modelData)
                        iconSize: 19
                        text: modelData.stateChanging ? (modelData.state === ConnectionState.Disconnecting ? "Disconnecting from " : "Connecting to ") + modelData.name : modelData.connected ? "Disconnect from " + modelData.name : "Connect to " + modelData.name
                        Layout.preferredWidth: 36
                        opacity: modelData.stateChanging || modelData.connected ? 1 : 0.55
                        onClicked: root.toggle(modelData)
                    }
                    Action {
                        Layout.fillWidth: true
                        text: modelData.name
                        ToolTip.text: root.networkDetails(modelData)
                        ToolTip.delay: 500
                        highlighted: root.selected === modelData
                        onClicked: root.toggle(modelData)
                        contentItem: RowLayout {
                            spacing: 6
                            Label { text: modelData.name; color: modelData.connected && !modelData.stateChanging ? Theme.text : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.selected === modelData && !modelData.connected && !modelData.stateChanging && (root.passwordNeeded || root.error !== "")
                    Layout.fillWidth: true
                    Layout.leftMargin: 40
                    spacing: 6
                    RowLayout {
                        visible: root.passwordNeeded
                        Layout.fillWidth: true
                        spacing: 4
                        SearchField {
                            Layout.fillWidth: true
                            placeholderText: WifiSecurityType.toString(modelData.security) + " network password"
                            echoMode: TextInput.Password
                            text: root.password
                            onTextChanged: root.password = text
                            onAccepted: root.connectSelected()
                        }
                        IconButton {
                            iconName: "link"
                            iconSize: 19
                            text: "Connect to " + modelData.name
                            enabled: root.password.length > 0
                            onClicked: root.connectSelected()
                        }
                        IconButton {
                            iconName: "x"
                            iconSize: 19
                            text: "Cancel connection"
                            onClicked: { root.selected = null; root.password = ""; root.error = ""; root.passwordNeeded = false; }
                        }
                    }
                    Label { text: root.error; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.danger }
                    IconButton {
                        visible: !root.passwordNeeded && root.error !== ""
                        iconName: "x"
                        iconSize: 19
                        text: "Dismiss connection error"
                        onClicked: { root.selected = null; root.error = ""; }
                    }
                }
            }
        }
        WheelScroll { view: list }
        ScrollBar.vertical: ScrollBar {}
    }
    Label { visible: Networking.wifiEnabled && !root.networks.length; text: "Searching for networks…"; color: Theme.muted }
    Connections {
        target: root.selected
        function onConnectionFailed(reason) {
            root.error = "Could not connect: " + ConnectionFailReason.toString(reason);
            if (root.supportsPassword) root.passwordNeeded = true;
        }
        function onConnectedChanged() {
            if (root.selected && root.selected.connected) {
                root.password = "";
                root.passwordNeeded = false;
                root.error = "";
            }
        }
    }
}
