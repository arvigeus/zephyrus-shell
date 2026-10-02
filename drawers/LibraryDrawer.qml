import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets"

DrawerFrame {
    signal searchRequested(string query)
    Keys.onPressed: event => {
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            searchRequested(event.text);
            event.accepted = true;
        }
    }
    headerContent: Component { UserProfileButton {} }
    headerActionText: "Reload spaces"
    onHeaderActionRequested: Plugins.reload()
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        Action {
            Layout.fillWidth: true
            text: "Type to search applications"; iconName: "search"; textAlignment: Text.AlignLeft
            onClicked: searchRequested("")
        }
        ScrollArea {
            id: spacesScroll
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: spacesScroll.availableWidth; spacing: 8
                Action {
                    Layout.fillWidth: true; implicitHeight: 52
                    text: "Desktop"; textAlignment: Text.AlignLeft
                    iconName: "monitor"
                    onClicked: ShellState.showDesktop()
                }
                Repeater {
                    model: Plugins.entries
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 4
                        Action {
                            Layout.fillWidth: true; implicitHeight: 52
                            text: modelData.name
                            textAlignment: Text.AlignLeft
                            iconName: modelData.icon
                            Accessible.description: ShellState.runningPluginIds.includes(modelData.id) ? "Running" : ""
                            onClicked: ShellState.openPlugin(modelData.id)
                        }
                        IconButton {
                            visible: ShellState.runningPluginIds.includes(modelData.id)
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            iconName: "x"; text: "Close " + modelData.name
                            onClicked: ShellState.stopPlugin(modelData.id)
                        }
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
