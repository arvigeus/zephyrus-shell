import QtQuick
import QtQuick.Layouts
import "../widgets"
import "../core"
ColumnLayout {
    id: root
    required property var machine
    signal openPage(string page)
    property bool expanded: false
    Layout.fillWidth: true; spacing: 4
    RowLayout {
        Layout.fillWidth: true
        Icon { name: "sun"; Layout.preferredWidth: 42 }
        LevelSlider {
            Layout.fillWidth: true; from: 5; to: 100; stepSize: 1
            value: root.machine.snapshot.brightness || 5
            enabled: !!root.machine.snapshot.brightnessAvailable && !root.machine.busy
            onMoved: commit.restart()
            Accessible.name: "Primary display brightness"
            Timer { id: commit; interval: 300; onTriggered: root.machine.run("brightness", Math.round(parent.value)) }
        }
        Label { text: root.machine.snapshot.brightnessAvailable ? root.machine.snapshot.brightness + "%" : "—"; color: Theme.muted; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
        IconButton { iconName: root.expanded ? "chevron-up" : "chevron-down"; text: "Choose primary display"; onClicked: root.expanded = !root.expanded }
    }
    ColumnLayout {
        visible: root.expanded; Layout.fillWidth: true; Layout.leftMargin: 48
        Repeater {
            model: root.machine.snapshot.monitors || []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                IconButton { iconName: modelData.disabled ? "monitor-off" : "monitor"; text: (modelData.disabled ? "Enable " : "Disable ") + modelData.label; enabled: !root.machine.busy; onClicked: root.machine.run("display", JSON.stringify({name: modelData.name, enabled: !!modelData.disabled})) }
                Action { text: modelData.label; Layout.fillWidth: true; enabled: !modelData.disabled && !root.machine.busy; highlighted: modelData.name === root.machine.snapshot.primary; onClicked: root.machine.run("primary", modelData.name) }
            }
        }
        Label { visible: !root.machine.snapshot.brightnessAvailable; text: "Brightness unavailable. External displays need a configured DDC bus."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Action { text: "Display settings"; Layout.fillWidth: true; onClicked: root.openPage("display") }
    }
}
