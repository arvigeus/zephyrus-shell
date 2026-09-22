import QtQuick
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    required property var machine
    property string pending: ""
    Layout.fillWidth: true
    RowLayout {
        Layout.fillWidth: true
        Repeater {
            model: [{id:"logout", label:"Log out", icon:"log-out"}, {id:"suspend", label:"Sleep", icon:"moon"}, {id:"reboot", label:"Restart", icon:"rotate-ccw"}, {id:"poweroff", label:"Power off", icon:"power"}]
            IconButton {
                iconName: modelData.icon
                required property var modelData
                text: modelData.label; Layout.fillWidth: true
                enabled: !root.machine.busy && (modelData.id !== "logout" || !!root.machine.snapshot.hyprland)
                onClicked: root.pending = modelData.id
            }
        }
    }
    RowLayout {
        visible: root.pending !== ""
        Layout.fillWidth: true
        Action { text: "Confirm " + root.pending; destructive: true; Layout.fillWidth: true; onClicked: { root.machine.run(root.pending); root.pending = ""; } }
        Action { text: "Cancel"; onClicked: root.pending = "" }
    }
}
