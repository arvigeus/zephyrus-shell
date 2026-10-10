import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets"

DrawerFrame {
    id: root
    signal searchRequested(string query)
    Keys.onPressed: event => {
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            searchRequested(event.text);
            event.accepted = true;
        }
    }
    headerContent: Component { UserProfileButton {} }
    headerActions: Component {
        IconButton {
            objectName: "spacesSearchButton"
            iconName: "search"; text: "Search applications and spaces"
            onClicked: root.searchRequested("")
        }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
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
                    model: Modules.entries
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 4
                        Action {
                            Layout.fillWidth: true; implicitHeight: 52
                            text: modelData.name
                            textAlignment: Text.AlignLeft
                            iconName: modelData.icon
                            Accessible.description: ShellState.runningModuleIds.includes(modelData.id) ? "Running" : ""
                            onClicked: ShellState.openModule(modelData.id)
                        }
                        IconButton {
                            visible: ShellState.runningModuleIds.includes(modelData.id)
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            iconName: "x"; text: "Close " + modelData.name
                            onClicked: ShellState.stopModule(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
