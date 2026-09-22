import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import "../widgets"
import "../core"

RowLayout {
    id: root
    signal openPage(string page)
    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var connectedNetworks: wifiDevices.reduce((all, device) => all.concat(device.networks.values), []).filter(network => network.connected)
    readonly property var adapter: Bluetooth.defaultAdapter
    Layout.fillWidth: true
    spacing: 12
    QuickTile {
        Layout.fillWidth: true; Layout.preferredWidth: 1
        title: "Wi-Fi"; symbol: on ? "wifi" : "wifi-off"
        available: root.wifiDevices.length > 0 && Networking.wifiHardwareEnabled
        on: Networking.wifiEnabled && available
        subtitle: !available ? "Unavailable" : !on ? "Off" : root.connectedNetworks.length ? root.connectedNetworks[0].name : "Not connected"
        onToggled: { Networking.wifiEnabled = !Networking.wifiEnabled; }
        onExpanded: root.openPage("wifi")
    }
    QuickTile {
        Layout.fillWidth: true; Layout.preferredWidth: 1
        title: "Bluetooth"; symbol: on ? "bluetooth" : "bluetooth-off"
        available: !!root.adapter
        on: available && root.adapter.enabled
        subtitle: !available ? "Unavailable" : !on ? "Off" : Bluetooth.devices.values.filter(device => device.connected).length + " connected"
        onToggled: { root.adapter.enabled = !root.adapter.enabled; }
        onExpanded: root.openPage("bluetooth")
    }
}
