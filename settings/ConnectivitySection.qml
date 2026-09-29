import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import "../widgets"
import "../core"
import "../core/StatusIcons.js" as StatusIcons

ColumnLayout {
    id: root
    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var connectedNetworks: wifiDevices.reduce((all, device) => all.concat(device.networks.values), []).filter(network => network.connected)
    readonly property var connectedNetwork: connectedNetworks.length ? connectedNetworks[0] : null
    readonly property var transitioningNetwork: wifiDevices.reduce((all, device) => all.concat(device.networks.values), []).find(network => network.stateChanging) || null
    readonly property string wifiStatus: transitioningNetwork ? (transitioningNetwork.state === ConnectionState.Disconnecting ? "Disconnecting " : "Connecting ") + transitioningNetwork.name + "…" : connectedNetworks.length ? connectedNetworks[0].name : Networking.wifiEnabled ? "Not connected" : "Off"
    readonly property var adapter: Bluetooth.defaultAdapter
    property bool wifiExpanded: false
    property bool bluetoothExpanded: false
    Layout.fillWidth: true
    spacing: 4
    RowLayout {
        Layout.fillWidth: true
        IconButton {
            iconName: !Networking.wifiEnabled ? "wifi-off" : root.transitioningNetwork ? "wifi-sync" : root.connectedNetwork ? StatusIcons.wifiIcon(root.connectedNetwork.signalStrength, ![WifiSecurityType.Open, WifiSecurityType.Owe, WifiSecurityType.Unknown].includes(root.connectedNetwork.security)) : "wifi"
            text: Networking.wifiEnabled ? "Turn off Wi-Fi" : "Turn on Wi-Fi"
            enabled: root.wifiDevices.length > 0 && Networking.wifiHardwareEnabled
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }
        Action {
            id: wifiHeader
            Layout.fillWidth: true
            text: "Wi-Fi: " + root.wifiStatus
            textAlignment: Text.AlignLeft
            contentItem: RowLayout {
                Label { text: wifiHeader.text; Layout.fillWidth: true; elide: Text.ElideRight }
            }
            onClicked: root.wifiExpanded = !root.wifiExpanded
        }
        IconButton { iconName: root.transitioningNetwork ? "wifi-sync" : root.wifiExpanded ? "chevron-up" : "chevron-down"; text: root.transitioningNetwork ? root.wifiStatus : "Choose Wi-Fi network"; onClicked: root.wifiExpanded = !root.wifiExpanded }
    }
    Loader { active: root.wifiExpanded; visible: active; Layout.fillWidth: true; Layout.leftMargin: 48; sourceComponent: WifiPage { compact: true } }
    RowLayout {
        Layout.fillWidth: true
        IconButton {
            iconName: root.adapter && root.adapter.enabled ? "bluetooth" : "bluetooth-off"
            text: root.adapter && root.adapter.enabled ? "Turn off Bluetooth" : "Turn on Bluetooth"
            enabled: !!root.adapter
            onClicked: root.adapter.enabled = !root.adapter.enabled
        }
        Action {
            Layout.fillWidth: true
            text: "Bluetooth: " + (!root.adapter ? "Unavailable" : !root.adapter.enabled ? "Off" : Bluetooth.devices.values.filter(device => device.connected).length + " connected")
            textAlignment: Text.AlignLeft
            onClicked: root.bluetoothExpanded = !root.bluetoothExpanded
        }
        IconButton { iconName: root.bluetoothExpanded ? "chevron-up" : "chevron-down"; text: "Choose Bluetooth device"; onClicked: root.bluetoothExpanded = !root.bluetoothExpanded }
    }
    Loader { active: root.bluetoothExpanded; visible: active; Layout.fillWidth: true; Layout.leftMargin: 48; sourceComponent: BluetoothPage { compact: true } }
}
