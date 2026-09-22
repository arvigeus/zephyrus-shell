import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"
import "../core"
ScrollArea {
    id: root
    required property var machine
    contentWidth: availableWidth; clip: true
    ColumnLayout {
        width: root.availableWidth; spacing: 16
        Label { text: "Primary selects the display controlled by brightness in this shell. Hyprland has no global primary-monitor setting. Display changes apply to this session."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted }
        Repeater {
            model: root.machine.snapshot.monitors || []
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Heading { text: modelData.label }
                Label { text: modelData.name + (modelData.disabled ? " · Disabled" : " · " + modelData.width + " × " + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz"); color: Theme.muted }
                Choice { Layout.fillWidth: true; model: modelData.availableModes || []; displayText: "Resolution & refresh rate"; enabled: !modelData.disabled && !root.machine.busy; onActivated: index => root.machine.run("display-mode", JSON.stringify({name: modelData.name, mode: model[index]})) }
                Choice { Layout.fillWidth: true; model: ["100%", "125%", "150%", "175%", "200%"] ; currentIndex: Math.round(((modelData.scale || 1) - 1) * 4); enabled: !modelData.disabled && !root.machine.busy; Accessible.name: "Display scale"; onActivated: index => root.machine.run("display-scale", JSON.stringify({name: modelData.name, scale: 1 + index / 4})) }
            }
        }
        Label { visible: !(root.machine.snapshot.monitors || []).length; text: "Display controls require a Hyprland session."; color: Theme.muted }
    }
}
