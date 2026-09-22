import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../core"
import "." as Widgets

Widgets.Action {
    id: root
    property var profile: ({name: Quickshell.env("USER"), username: Quickshell.env("USER"), avatar: "", home: Quickshell.env("HOME")})
    text: "Open user profile"
    implicitHeight: 58
    leftPadding: 0; rightPadding: 4
    contentItem: RowLayout {
        spacing: 12
        Item {
            Layout.preferredWidth: 42; Layout.preferredHeight: 42
            Image { id: avatar; anchors.fill: parent; source: root.profile.avatar; fillMode: Image.PreserveAspectFit }
            Icon { anchors.centerIn: parent; width: 32; height: 32; name: "user-round"; visible: !avatar.source.toString() || avatar.status === Image.Error }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4
            Widgets.Label { text: root.profile.name; font.pixelSize: 20; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Widgets.Label { text: "@" + root.profile.username; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
    onClicked: ShellState.openProfile(profile)
    Process {
        command: ["python3", Paths.file("scripts/user_profile.py")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.profile = JSON.parse(text); }
                catch (error) { console.warn("Could not read user profile:", error); }
            }
        }
    }
}
