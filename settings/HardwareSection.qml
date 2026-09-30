import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../core"
import "../widgets"

RowLayout {
    id: root
    required property var machine
    signal openPage(string page)
    readonly property var hw: machine.snapshot.hardware || ({})
    Layout.fillWidth: true
    spacing: 8
    Repeater {
        model: ["cpu", "gpu"]
        Rectangle {
                id: card
                required property string modelData
                readonly property var gpu: root.machine.snapshot.gpu || ({modes: []})
                readonly property var temperature: modelData === "cpu" ? root.hw.cpuTemperature : root.hw.gpuTemperature
                readonly property bool usageAvailable: modelData === "cpu" ? root.hw.cpuPercent !== undefined : root.hw.gpuPercent !== null && root.hw.gpuPercent !== undefined
                readonly property real usage: modelData === "cpu" ? root.hw.cpuPercent || 0 : root.hw.gpuPercent || 0
                readonly property var modes: modelData === "cpu" ? [
                    {value: "power-saver", label: "Power saver", icon: "leaf"},
                    {value: "balanced", label: "Balanced", icon: "scale"},
                    {value: "performance", label: "Performance", icon: "rocket"}
                ] : [
                    {value: "integrated", label: "Integrated", icon: "square-dot"},
                    {value: "hybrid", label: "Hybrid", icon: "squares-exclude"},
                    {value: "smart", label: "Smart", icon: "square-sparkles"}
                ]
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumHeight: 190
                Layout.preferredHeight: 190
                color: Theme.surface
                radius: Theme.controlRadius

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 5
                    Action {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        text: card.modelData === "cpu" ? root.hw.cpuName || "Processor" : root.hw.gpuName || "Graphics"
                        background: Rectangle { radius: Theme.controlRadius; color: parent.hovered ? Theme.raised : "transparent"; border.color: parent.activeFocus ? Theme.accent : "transparent" }
                        contentItem: RowLayout {
                            spacing: 5
                            Icon { name: card.modelData; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                            Label {
                                text: card.modelData === "cpu" ? root.hw.cpuName || "Processor" : root.hw.gpuName || "Graphics"
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                font.pixelSize: 11
                            }
                        }
                        onClicked: root.openPage(card.modelData)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Icon { name: "thermometer"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                        Label {
                            text: card.temperature ? card.temperature.value + "°C" : "Unavailable"
                            color: Theme.muted; font.pixelSize: 11
                            Controls.ToolTip.visible: temperatureHover.hovered
                            Controls.ToolTip.text: (card.temperature ? card.temperature.driver + " · " + card.temperature.label + "\n" : "")
                                + "Sampled on opening or refresh"
                            HoverHandler { id: temperatureHover }
                        }
                    }
                    UsageBar { Layout.fillWidth: true; percent: card.usage; available: card.usageAvailable }
                    Label { text: card.usageAvailable ? Math.round(card.usage) + "% used" : "Usage unavailable"; color: Theme.muted; font.pixelSize: 11 }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: card.modes
                            IconButton {
                                required property var modelData
                                Layout.fillWidth: true
                                iconName: modelData.icon
                                iconSize: 18
                                text: modelData.label
                                highlighted: card.modelData === "cpu" ? root.machine.snapshot.profile === modelData.value : card.gpu.mode === modelData.value
                                enabled: !root.machine.busy && !Profiles.busy && (card.modelData === "cpu" ? (root.machine.snapshot.profiles || []).includes(modelData.value) : (card.gpu.modes || []).includes(modelData.value))
                                onClicked: root.machine.run(card.modelData === "cpu" ? "profile" : "gpu", modelData.value)
                            }
                        }
                    }
                }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumHeight: 190
        Layout.preferredHeight: 190
        color: Theme.surface
        radius: Theme.controlRadius
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5
            Action {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                text: "System"
                background: Rectangle { radius: Theme.controlRadius; color: parent.hovered ? Theme.raised : "transparent"; border.color: parent.activeFocus ? Theme.accent : "transparent" }
                contentItem: RowLayout {
                    spacing: 5
                    Icon { name: "hard-drive"; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                    Label { text: "System"; Layout.fillWidth: true; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Icon { name: "chevron-right"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; opacity: 0.6 }
                }
                onClicked: root.openPage("system")
            }
            RowLayout {
                Layout.fillWidth: true
                Icon { name: "memory-stick"; Layout.preferredWidth: 15; Layout.preferredHeight: 15 }
                Label { text: "Memory"; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: Math.round(root.hw.memoryPercent || 0) + "%"; color: Theme.muted; font.pixelSize: 11 }
            }
            UsageBar { Layout.fillWidth: true; percent: root.hw.memoryPercent || 0 }
            RowLayout {
                Layout.fillWidth: true
                Icon { name: "hard-drive"; Layout.preferredWidth: 15; Layout.preferredHeight: 15 }
                Label { text: "Storage"; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: Math.round(root.hw.storagePercent || 0) + "%"; color: Theme.muted; font.pixelSize: 11 }
            }
            UsageBar { Layout.fillWidth: true; percent: root.hw.storagePercent || 0 }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                IconButton {
                    iconName: "upload"
                    iconSize: 18
                    text: "Update the system"
                    onClicked: {}
                }
                HoldAction {
                    iconName: "brush-cleaning"
                    iconSize: 18
                    text: "Hold to remove cached image previews"
                    enabled: !root.machine.busy
                    onActivated: root.machine.run("clean-thumbnails", "confirm")
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
