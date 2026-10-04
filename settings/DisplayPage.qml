import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

ScrollArea {
    id: root
    objectName: "display-page"
    required property var machine
    readonly property var monitors: machine.snapshot.monitors || []
    readonly property var enabledMonitors: monitors.filter(m => !m.disabled)
    function moveMonitor(name, direction) {
        const order = enabledMonitors.map(m => m.name);
        const index = order.indexOf(name);
        const target = index + direction;
        if (index < 0 || target < 0 || target >= order.length) return;
        [order[index], order[target]] = [order[target], order[index]];
        machine.run("display-order", JSON.stringify({order: order}));
    }
    contentWidth: availableWidth; clip: true
    ColumnLayout {
        width: root.availableWidth; spacing: 16
        Label { text: "Display changes are remembered for this monitor setup."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Action { objectName: "display-save"; text: "Remember current layout"; iconName: "save"; Layout.fillWidth: true; enabled: root.enabledMonitors.length > 0 && !root.machine.busy; onClicked: root.machine.run("display-save") }
        Heading { text: "Monitor order" }
        Repeater {
            model: root.enabledMonitors
            RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Icon { name: "monitor"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                Label { text: (index + 1) + ". " + modelData.label; Layout.fillWidth: true; elide: Text.ElideRight }
                IconButton { iconName: "chevron-left"; text: "Move " + modelData.label + " left"; enabled: index > 0 && !root.machine.busy; onClicked: root.moveMonitor(modelData.name, -1) }
                IconButton { iconName: "chevron-right"; text: "Move " + modelData.label + " right"; enabled: index < root.enabledMonitors.length - 1 && !root.machine.busy; onClicked: root.moveMonitor(modelData.name, 1) }
            }
        }
        Repeater {
            model: root.monitors
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 8
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true
                    Heading { text: modelData.label; Layout.fillWidth: true; elide: Text.ElideRight }
                    IconButton { iconName: modelData.disabled ? "monitor-off" : "monitor"; text: modelData.disabled ? "Enable display" : "Turn off display"; highlighted: !!modelData.disabled; enabled: !root.machine.busy && (modelData.disabled || root.enabledMonitors.length > 1); onClicked: root.machine.run("display", JSON.stringify({name: modelData.name, enabled: !!modelData.disabled})) }
                }
                Label { text: modelData.name + (modelData.disabled ? " · Disabled" : " · " + modelData.width + " × " + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz"); color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Action { text: modelData.name === root.machine.snapshot.primary ? "Brightness display" : "Use for brightness"; iconName: "sun"; highlighted: modelData.name === root.machine.snapshot.primary; Layout.fillWidth: true; enabled: !modelData.disabled && !root.machine.busy; onClicked: root.machine.run("primary", modelData.name) }
                Label { text: "Resolution & refresh rate"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                Choice {
                    Layout.fillWidth: true
                    model: modelData.availableModes || []
                    currentIndex: model.findIndex(mode => mode.startsWith(modelData.width + "x" + modelData.height + "@") && Math.abs(parseFloat(mode.split("@")[1]) - modelData.refreshRate) < 0.1)
                    enabled: !modelData.disabled && !root.machine.busy
                    Accessible.name: "Resolution and refresh rate for " + modelData.label
                    onActivated: index => root.machine.run("display-mode", JSON.stringify({name: modelData.name, mode: model[index]}))
                }
                Label { text: "Scale"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                Choice { Layout.fillWidth: true; model: ["100%", "125%", "150%", "175%", "200%"] ; currentIndex: Math.round(((modelData.scale || 1) - 1) * 4); enabled: !modelData.disabled && !root.machine.busy; Accessible.name: "Display scale"; onActivated: index => root.machine.run("display-scale", JSON.stringify({name: modelData.name, scale: 1 + index / 4})) }
                ColumnLayout {
                    visible: !modelData.name.startsWith("eDP") && !modelData.name.startsWith("LVDS")
                    Layout.fillWidth: true
                    Label { text: "Brightness connection"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                    Choice {
                        readonly property var buses: root.machine.snapshot.ddcBuses || []
                        model: ["Automatic"].concat(buses.map(bus => "I²C bus " + bus))
                        displayText: modelData.ddcBus === null ? "Automatic · No bus detected" : "Detected bus " + modelData.ddcBus
                        Layout.fillWidth: true; enabled: !root.machine.busy
                        Accessible.name: "DDC bus for " + modelData.label
                        ToolTip.visible: hovered || activeFocus
                        ToolTip.text: "Automatic uses the monitor connector. Enable DDC/CI in the monitor menu."
                        ToolTip.delay: 800
                        onActivated: index => root.machine.run("display-ddc", JSON.stringify({name: modelData.name, bus: index === 0 ? null : buses[index - 1]}))
                    }
                }
            }
        }
        Label { visible: !root.monitors.length; text: "Display controls require a Hyprland session."; color: Theme.muted }
    }
}
