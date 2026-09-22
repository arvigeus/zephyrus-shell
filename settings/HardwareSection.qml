import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"
RowLayout {
    id: root
    required property var machine
    signal openPage(string page)
    Layout.fillWidth: true; spacing: 10
    Repeater {
        model: ["cpu", "gpu", "memory"]
        Rectangle {
            id: card
            required property string modelData
            readonly property var hw: root.machine.snapshot.hardware || ({})
            readonly property var cpuTemperatures: (hw.temperatures || []).filter(t => /k10temp|coretemp|zenpower/.test(t.driver))
            readonly property var gpu: root.machine.snapshot.gpu || ({modes: []})
            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 140
            color: Theme.surface; radius: Theme.controlRadius; border.color: "transparent"
            Rectangle { x: 8; y: 0; width: 24; height: 1; color: Theme.accent }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 6
                Action {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    text: "Open " + card.modelData + " details"
                    background: Rectangle { radius: Theme.controlRadius; color: parent.hovered ? Theme.raised : "transparent"; border.color: parent.activeFocus ? Theme.accent : "transparent" }
                    contentItem: ColumnLayout {
                        RowLayout { Icon { name: card.modelData === "memory" ? "memory-stick" : card.modelData } Label { text: card.modelData === "memory" ? "RAM" : card.modelData.toUpperCase(); color: Theme.muted; font.pixelSize: 11 } }
                        Label { text: card.modelData === "cpu" ? (card.cpuTemperatures.length ? card.cpuTemperatures[0].value + "°C" : "—") : card.modelData === "gpu" ? (card.gpu.mode || "Unavailable") : (card.hw.memoryPercent || 0) + "% used"; font.pixelSize: 16; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    onClicked: root.openPage(card.modelData)
                }
                Choice {
                    visible: card.modelData !== "memory"; Layout.fillWidth: true; implicitHeight: 34
                    model: card.modelData === "cpu" ? (root.machine.snapshot.profiles || []) : card.gpu.modes
                    displayText: card.modelData === "cpu" ? ({"power-saver": "Quiet", "balanced": "Balanced", "performance": "Performance"})[root.machine.snapshot.profile] || "Unavailable" : card.gpu.mode || "Unavailable"
                    enabled: model && model.length > 0 && !root.machine.busy && !Profiles.busy
                    onActivated: index => root.machine.run(card.modelData === "cpu" ? "profile" : "gpu", model[index])
                }
                Label { visible: card.modelData === "memory"; text: (card.hw.memoryUsed || 0) + " / " + (card.hw.memoryTotal || 0) + " GiB"; color: Theme.muted; font.pixelSize: 12; Layout.preferredHeight: 34; verticalAlignment: Text.AlignVCenter }
            }
        }
    }
}
