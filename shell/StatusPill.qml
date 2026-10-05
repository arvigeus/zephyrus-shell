import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "../core"
import "../core/StatusIcons.js" as StatusIcons
import "../widgets"

BarAction {
    id: root
    text: "Open Settings"
    ToolTip.visible: false
    Accessible.description: [
        Networking.wifiEnabled ? wifiDescription : "",
        Warp.state === "connected" ? "Cloudflare WARP connected" : "",
        adapter && adapter.enabled ? "Bluetooth on, " + bluetoothConnections + " connected" : "",
        !sink ? "Speakers unavailable" : sink.audio.muted ? "Speakers muted" : "Volume " + Math.round(sink.audio.volume * 100) + "%",
        microphoneEnabled ? "Microphone enabled" : "",
        batteryPresent ? batteryDescription : "",
        powerMode ? "Power mode " + powerMode.replace(/-/g, " ") : "Power mode unavailable",
        KeepAwake.active ? (KeepAwake.mode === "screen" ? "Keep screen on" : "Keep awake") : "",
        "GPU selection per application"
    ].filter(Boolean).join("; ")

    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var networks: wifiDevices.reduce((all, device) => all.concat(device.networks.values), [])
    readonly property var connectedNetwork: networks.find(network => network.connected) || null
    readonly property var transitioningNetwork: networks.find(network => network.stateChanging) || null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int bluetoothConnections: Bluetooth.devices.values.filter(device => device.connected).length
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sources: Pipewire.nodes.values.filter(node => !node.isStream && node.audio && !node.isSink)
    readonly property bool microphoneEnabled: sources.some(node => !node.audio.muted)
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryPresent: !!battery && battery.isPresent
    readonly property real batteryPercent: batteryPresent ? battery.percentage * 100 : 0
    readonly property var snapshot: HardwareSnapshot.data
    readonly property string powerMode: snapshot.profile || ""
    readonly property string gpuMode: snapshot.gpu ? snapshot.gpu.mode || "" : ""
    readonly property string wifiIcon: transitioningNetwork ? "wifi-sync" : connectedNetwork ? StatusIcons.wifiIcon(connectedNetwork.signalStrength, ![WifiSecurityType.Open, WifiSecurityType.Owe, WifiSecurityType.Unknown].includes(connectedNetwork.security)) : "wifi"
    readonly property string wifiDescription: transitioningNetwork ? (transitioningNetwork.state === ConnectionState.Disconnecting ? "Disconnecting from " : "Connecting to ") + transitioningNetwork.name : connectedNetwork ? "Wi-Fi: " + connectedNetwork.name + " · " + Math.round((Number(connectedNetwork.signalStrength) || 0) * 100) + "% signal" : "Wi-Fi on · Not connected"
    readonly property string batteryDescription: batteryDetails()

    function batteryDetails() {
        if (!batteryPresent) return "Battery unavailable";
        let details = "Battery: " + Math.round(batteryPercent) + "%";
        const charging = battery.state === UPowerDeviceState.Charging;
        const discharging = battery.state === UPowerDeviceState.Discharging;
        const seconds = charging ? battery.timeToFull : discharging ? battery.timeToEmpty : 0;
        if (battery.state === UPowerDeviceState.FullyCharged) details += " · Fully charged";
        else if (charging) details += " · Charging";
        if (seconds > 0) {
            const minutes = Math.round(seconds / 60);
            details += " · " + Math.floor(minutes / 60) + "h " + minutes % 60 + "m " + (charging ? "until charged" : "remaining");
        }
        const watts = Math.abs(Number(battery.changeRate) || 0);
        if (watts >= 0.1) details += " · " + watts.toFixed(1) + " W";
        return details;
    }

    PwObjectTracker { objects: root.sources.concat(root.sink ? [root.sink] : []) }

    contentItem: RowLayout {
        spacing: 8
        Item {
            objectName: "warp-status-icon"
            visible: Warp.state === "connected"
            Layout.preferredWidth: 23
            Layout.preferredHeight: 19
            AppIcon { anchors.centerIn: parent; width: 23; height: 19; artwork: Warp.artwork }
            HoverHandler { id: warpHover }
            ToolTip.visible: warpHover.hovered
            ToolTip.text: "Cloudflare WARP connected"
            ToolTip.delay: 500
        }
        PillStatusIcon { visible: Networking.wifiEnabled; name: root.wifiIcon; description: root.wifiDescription }
        PillStatusIcon { visible: !!root.adapter && root.adapter.enabled; name: "bluetooth"; description: "Bluetooth: " + root.bluetoothConnections + " connected" }
        PillStatusIcon { name: StatusIcons.volumeIcon(root.sink ? root.sink.audio.volume : 0, !root.sink || root.sink.audio.muted); description: !root.sink ? "Speakers unavailable" : root.sink.audio.muted ? "Speakers muted" : "Volume: " + Math.round(root.sink.audio.volume * 100) + "%" }
        PillStatusIcon { visible: root.microphoneEnabled; name: "mic"; description: "Microphone enabled" }
        PillStatusIcon { visible: root.batteryPresent; name: StatusIcons.batteryIcon(root.batteryPercent, root.battery.state === UPowerDeviceState.Charging); description: root.batteryDescription }
        PillStatusIcon { name: StatusIcons.profileIcon(root.powerMode); description: root.powerMode ? "Power mode: " + root.powerMode.replace(/-/g, " ") : "Power mode unavailable" }
        PillStatusIcon { visible: KeepAwake.active; name: KeepAwake.mode === "screen" ? "eye" : "coffee"; description: KeepAwake.mode === "screen" ? "Keep screen on" : "Keep awake" }
        PillStatusIcon { name: "gpu"; description: "GPU selection: per application. Choose a GPU in Applications; firmware modes are in ROG Control Center." }
    }
}
