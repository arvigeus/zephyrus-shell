import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets"

DrawerFrame {
    headerContent: Component { UserProfileButton {} }
    headerActionText: "Reload spaces"
    onHeaderActionRequested: Plugins.reload()
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        ScrollView {
            id: spacesScroll
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: spacesScroll.availableWidth; spacing: 8
                Repeater {
                    model: Plugins.entries
                    Action {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 52
                        text: modelData.name
                        iconName: modelData.icon
                        onClicked: ShellState.openPlugin(modelData.id)
                    }
                }
                Label { visible: Plugins.entries.length === 0; text: "No spaces installed yet."; color: Theme.muted }
                Repeater {
                    model: Plugins.errors
                    Label { required property string modelData; text: modelData; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
        }
    }
}
