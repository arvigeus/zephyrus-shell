import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "." as Widgets

Rectangle {
    color: Theme.background; radius: Theme.radius; border.color: Theme.border
    readonly property var profile: ShellState.userProfile
    Shortcut { sequence: "Escape"; onActivated: ShellState.close() }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20; spacing: 12
        Widgets.Label { text: "User profile"; font.pixelSize: 18 }
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72; Layout.preferredHeight: 72
            Image { id: avatar; anchors.fill: parent; source: profile.avatar || ""; fillMode: Image.PreserveAspectFit }
            Icon { anchors.centerIn: parent; width: 48; height: 48; name: "user-round"; visible: !avatar.source.toString() || avatar.status === Image.Error }
        }
        Widgets.Label { text: profile.name || ""; font.pixelSize: 22; Layout.fillWidth: true; elide: Text.ElideRight }
        Widgets.Label { text: "@" + (profile.username || ""); color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
        Widgets.Label { text: profile.home || ""; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
        Item { Layout.fillHeight: true }
        Widgets.Action { text: "Close"; Layout.fillWidth: true; onClicked: ShellState.close() }
    }
}
