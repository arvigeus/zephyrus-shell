import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../settings"
import "../core"
import "../widgets"

DrawerFrame {
    id: root
    property string page: ""
    property bool expandSections: false
    title: ({wifi: "Wi-Fi", bluetooth: "Bluetooth", display: "Displays", cpu: "Processor", gpu: "Graphics", memory: "Memory"})[page] || "Settings"
    canGoBack: page !== ""
    backLabel: "Back to Settings"
    onBackRequested: page = ""
    subtitle: machineService.snapshot.model || "Your machine"
    headerActionText: "Refresh hardware readings"
    headerActionEnabled: !machineService.busy
    onHeaderActionRequested: machineService.refresh()
    Machine { id: machineService }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        Loader {
            visible: active; active: root.page !== ""
            Layout.fillWidth: true; Layout.fillHeight: true
            sourceComponent: root.page === "wifi" ? wifiPage : root.page === "bluetooth" ? bluetoothPage : root.page === "display" ? displayPage : hardwarePage
        }
        Component { id: wifiPage; WifiPage {} }
        Component { id: bluetoothPage; BluetoothPage {} }
        Component { id: displayPage; DisplayPage { machine: machineService } }
        Component { id: hardwarePage; HardwarePage { machine: machineService; page: root.page } }
        ScrollArea {
            id: controlScroll
            visible: root.page === ""
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: controlScroll.availableWidth; spacing: 16
                enabled: !Profiles.applying
                RowLayout {
                    Layout.fillWidth: true
                    Item {
                        Layout.preferredWidth: 38; Layout.preferredHeight: 30
                        Image { anchors.fill: parent; source: "../assets/asus-rog-logo.svg"; visible: !!machineService.snapshot.asus; sourceSize.width: 38; sourceSize.height: 30; fillMode: Image.PreserveAspectFit }
                    }
                    Choice { Layout.fillWidth: true; model: Profiles.names; displayText: Profiles.data.active || "Loading profiles…"; enabled: Profiles.loaded && !Profiles.busy && !machineService.busy; Accessible.name: "Settings profile"; onActivated: index => Profiles.select(model[index]) }
                }
                ConnectivitySection { onOpenPage: page => root.page = page }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    AudioSection { expanded: root.expandSections }
                    DisplaySection { expanded: root.expandSections; machine: machineService; onOpenPage: page => root.page = page }
                    PowerSection { expanded: root.expandSections; machine: machineService }
                }
                HardwareSection { machine: machineService; onOpenPage: page => root.page = page }
                Action { text: Attention.quiet ? "Do not disturb · On" : "Do not disturb · Off"; Layout.fillWidth: true; highlighted: Attention.quiet; onClicked: Attention.quiet = !Attention.quiet }
            }
        }
        Label { visible: text !== ""; text: machineService.error || Profiles.error; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
        SessionActions { visible: root.page === ""; machine: machineService }
    }
}
