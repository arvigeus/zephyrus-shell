import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../widgets"
import "../core"
import "../core/StatusIcons.js" as StatusIcons
ColumnLayout {
    id: root
    required property var machine
    property bool expanded: false
    readonly property var battery: UPower.displayDevice
    readonly property real percent: battery && battery.isPresent ? battery.percentage * 100 : machine.snapshot.batteryPercent || 0
    Layout.fillWidth: true; spacing: 4
    RowLayout {
        Layout.fillWidth: true
        Icon { name: StatusIcons.batteryIcon(root.percent, root.battery && root.battery.isPresent ? root.battery.state === UPowerDeviceState.Charging : root.machine.snapshot.batteryStatus === "Charging"); Layout.preferredWidth: 42 }
        Slider {
            id: limit
            Layout.fillWidth: true; implicitHeight: 42
            from: 50; to: 100; stepSize: 1
            value: Number(root.machine.snapshot.chargeLimit || 100)
            enabled: !!root.machine.snapshot.chargeLimit && !root.machine.busy
            Accessible.name: "Battery charge limit"
            onMoved: if (!pressed) chargeCommit.restart()
            onPressedChanged: if (!pressed) chargeCommit.restart()
            Timer { id: chargeCommit; interval: 600; onTriggered: root.machine.run("chargeLimit", Math.round(limit.value)) }
            ToolTip.visible: hovered || pressed
            ToolTip.text: enabled ? "Charge limit · " + Math.round(value) + "%" : "Charge limit unavailable"
            // The whole bar represents 0–100%; the handle's editable range is 50–100%.
            leftPadding: width / 2
            handle: Rectangle { visible: limit.enabled; x: limit.leftPadding + limit.position * limit.availableWidth - width / 2; y: (limit.height - height) / 2; width: 4; height: 24; radius: 2; color: Theme.text }
            background: Item {
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: limit.width; height: 12; radius: 4; color: Theme.raised
                    Rectangle { width: parent.width * root.percent / 100; height: parent.height; radius: 4; color: root.percent < 20 ? Theme.danger : Theme.accent }
                }
            }
        }
        Label { text: root.machine.snapshot.battery ? Math.round(root.percent) + "%" : "—"; color: Theme.muted; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
        IconButton { text: "Battery information"; iconName: root.expanded ? "chevron-up" : "chevron-down"; onClicked: root.expanded = !root.expanded }
    }
    Label { Layout.leftMargin: 48; Layout.fillWidth: true; text: root.machine.snapshot.batteryInfo || "No battery detected"; color: Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap }
    Loader {
        id: detailsLoader
        objectName: "batteryDetailsLoader"
        visible: active; active: root.expanded; asynchronous: true
        Layout.fillWidth: true; Layout.leftMargin: 48
        sourceComponent: BatteryDetails { machine: root.machine }
    }
    Label {
        visible: root.expanded && detailsLoader.status === Loader.Loading
        Layout.leftMargin: 48; Layout.fillWidth: true
        text: "Reading battery information…"; color: Theme.muted; font.pixelSize: 12
    }
}
