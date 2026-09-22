import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets"
ScrollArea {
    id: root
    required property var machine
    property string page: "cpu"
    readonly property var hw: machine.snapshot.hardware || ({})
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
        width: root.availableWidth; spacing: 16
        Heading { text: root.page === "memory" ? "MEMORY" : root.page.toUpperCase() }
        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; text: root.page === "cpu" ? "Load average · " + (root.hw.load || "—") + "\nCPU boost · " + (root.hw.boost === "1" ? "Enabled" : root.hw.boost === "0" ? "Disabled" : "Unavailable") : root.page === "memory" ? (root.hw.memoryUsed || 0) + " GiB used of " + (root.hw.memoryTotal || 0) + " GiB\nMemory is managed automatically by Linux." : ((root.machine.snapshot.gpu || {}).error || "Cardwire controls GPU access. Integrated saves power; Hybrid allows both GPUs; Smart allows GPU access per application. Modes available depend on your hardware.") }
        Heading { text: "SENSORS"; visible: root.page !== "memory" }
        Repeater { model: (root.hw.temperatures || []).filter(t => root.page === "gpu" ? /amdgpu|nouveau|nvidia/.test(t.driver) : root.page === "cpu" ? /k10temp|coretemp|zenpower|acpitz/.test(t.driver) : false); Label { required property var modelData; text: modelData.label + " · " + modelData.value + "°C"; color: Theme.muted } }
        Repeater { model: root.page === "cpu" ? root.hw.fans || [] : []; Label { required property var modelData; text: modelData.label + " · " + modelData.value + " RPM"; color: Theme.muted } }
        Label { visible: root.page === "cpu"; text: "Fan curves and power limits are managed by your firmware / ASUS configuration."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted }
        Action { text: "Refresh readings"; enabled: !root.machine.busy; onClicked: root.machine.refresh() }
    }
}
