import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    required property var machine
    property var batteries: []
    property bool loaded: false
    property string error: ""
    property bool refreshPending: false
    readonly property bool loading: query.running
    spacing: 8

    function refresh() {
        if (query.running) { refreshPending = true; return; }
        error = "";
        query.running = true;
    }
    function timeText(pack) {
        if (pack.externalPower === true && pack.status !== "Charging") return "";
        if (!(pack.seconds > 0)) return pack.status === "Charging" || pack.status === "Discharging" ? "Time estimate unavailable" : "";
        const minutes = Math.max(1, Math.round(pack.seconds / 60));
        const hours = Math.floor(minutes / 60);
        const duration = (hours ? hours + (hours === 1 ? " hour" : " hours") : "")
            + (hours && minutes % 60 ? " " : "")
            + (minutes % 60 ? minutes % 60 + " min" : "");
        return "About " + duration + (pack.status === "Charging"
            ? pack.chargeLimit < 100 ? " until " + Math.round(pack.chargeLimit) + "% charge limit" : " until full"
            : " remaining");
    }
    function capacityText(pack) {
        if (pack.fullCapacity === null) return "Capacity unavailable";
        const digits = pack.capacityUnit === "Wh" ? 1 : 0;
        return "Holds " + Number(pack.fullCapacity).toFixed(digits)
            + (pack.designCapacity === null ? " " + pack.capacityUnit + " · Original capacity unavailable"
                : " of its original " + Number(pack.designCapacity).toFixed(digits) + " " + pack.capacityUnit);
    }
    function powerText(pack) {
        if (pack.watts === null) return "Unavailable";
        const watts = Number(pack.watts);
        return watts.toFixed(1) + " W" + (watts === 0 && ["Full", "Not charging"].includes(pack.status) ? " · Idle" : "");
    }
    function powerDescription(pack) {
        return pack.status === "Discharging" ? pack.externalPower === true
            ? "Power supplied by the battery while external power is connected. Total laptop power use is not measured here."
            : "Power supplied by the battery to the laptop."
            : pack.status === "Charging" ? "Power going into the battery, excluding the laptop's other power use."
            : "Power flowing through the battery. The laptop's power use from the adapter is not measured here.";
    }

    Component.onCompleted: refresh()
    Connections { target: root.machine; enabled: root.visible; function onSnapshotChanged() { root.refresh(); } }
    onVisibleChanged: if (visible && loaded) refresh()
    Timer {
        interval: 5000; repeat: true; running: root.visible && root.loaded
        onTriggered: root.refresh()
    }
    Process {
        id: query
        command: ["python3", Paths.file("scripts/machine.py"), "battery-details"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error) root.error = result.error;
                    else { root.batteries = result.batteries; root.loaded = true; }
                } catch (exception) { root.error = "Could not read battery information."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.error) root.error = "Could not read battery information.";
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }
    Component.onDestruction: query.running = false

    Label {
        visible: !root.loaded && root.error === ""
        text: "Reading battery information…"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12)
        Layout.fillWidth: true
    }
    RowLayout {
        visible: root.error !== ""
        Layout.fillWidth: true
        Label { text: root.error; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
        IconButton { iconName: "refresh-cw"; text: "Retry battery information"; enabled: !root.loading; onClicked: root.refresh() }
    }
    Label {
        visible: root.loaded && root.batteries.length === 0
        text: "No laptop battery detected."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12)
        Layout.fillWidth: true
    }
    Repeater {
        model: root.batteries
        Rectangle {
            id: card
            required property var modelData
            readonly property bool healthAvailable: modelData.healthPercent !== null
            Layout.fillWidth: true
            implicitHeight: content.implicitHeight + 24
            radius: Theme.controlRadius
            color: Theme.surface
            ColumnLayout {
                id: content
                anchors.fill: parent; anchors.margins: 12
                spacing: 8
                Label {
                    id: timeEstimate
                    text: root.timeText(card.modelData)
                    visible: text !== ""; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12)
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                Rectangle { visible: timeEstimate.visible; Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true
                    Icon { name: "battery-full"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                    Label { text: "Battery health"; Layout.fillWidth: true; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                    Label { text: card.healthAvailable ? Math.round(card.modelData.healthPercent) + "%" : "Unavailable"; font.weight: Font.DemiBold; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                }
                Rectangle {
                    visible: card.healthAvailable
                    Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: Theme.raised
                    Rectangle {
                        width: parent.width * Math.min(100, Math.max(0, card.modelData.healthPercent || 0)) / 100
                        height: parent.height; radius: 3
                        color: card.modelData.healthPercent < 60 ? Theme.danger : card.modelData.healthPercent < 80 ? Theme.warning : Theme.success
                    }
                }
                Label {
                    text: root.capacityText(card.modelData)
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12)
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
                Repeater {
                    model: [
                        {icon: "power", label: "Battery power", value: root.powerText(card.modelData), description: root.powerDescription(card.modelData)},
                        {icon: "repeat", label: "Charge cycles", value: card.modelData.cycles === null ? "Unavailable" : String(Math.round(card.modelData.cycles))},
                        {icon: "thermometer", label: "Temperature", value: card.modelData.temperature === null ? "" : Number(card.modelData.temperature).toFixed(1) + "°C"}
                    ]
                    RowLayout {
                        required property var modelData
                        visible: modelData.value !== ""; Layout.fillWidth: true
                        Controls.ToolTip.visible: rowHover.hovered && !!modelData.description
                        Controls.ToolTip.text: modelData.description || ""
                        Controls.ToolTip.delay: 500
                        HoverHandler { id: rowHover }
                        Icon { name: modelData.icon; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                        Label { text: modelData.label; font.family: Theme.font; font.pixelSize: Theme.sp(12); color: Theme.muted; Layout.fillWidth: true }
                        Label { text: modelData.value; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                    }
                }
                Label {
                    text: [card.modelData.manufacturer, card.modelData.model, card.modelData.technology].filter(Boolean).join(" · ") || card.modelData.name
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11)
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                }
            }
        }
    }
}
