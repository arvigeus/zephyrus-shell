import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    objectName: "vpn-network-row"
    required property var profile
    required property var service
    spacing: 4
    readonly property bool pending: service.pendingProfile === profile.id
    readonly property string actionText: (profile.active ? "Disconnect from " : "Connect to ") + profile.name
    readonly property string errorText: service.errorProfile === profile.id ? service.error : profile.error
    readonly property bool canToggle: service.available && !service.busy && !service.refreshing && !profile.transitioning && (profile.active || !profile.error)

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        IconButton {
            objectName: "vpn-network-icon"
            iconName: "shield-lock"
            iconSize: 19
            Layout.preferredWidth: 36
            text: root.actionText
            enabled: root.canToggle
            opacity: root.profile.connected || root.profile.transitioning || root.pending ? 1 : 0.55
            onClicked: root.service.toggle(root.profile)
        }
        Action {
            objectName: "vpn-network-toggle"
            Layout.fillWidth: true
            text: root.actionText
            toolTip: "WireGuard · " + root.profile.name
            enabled: root.canToggle
            onClicked: root.service.toggle(root.profile)
            contentItem: RowLayout {
                spacing: 6
                Label { objectName: "vpn-network-name"; text: root.profile.name; color: root.profile.connected ? Theme.text : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                Label {
                    objectName: "vpn-network-status"
                    text: root.pending ? root.service.pendingAction === "disconnect" ? "Disconnecting…" : "Connecting…" : root.profile.status
                    visible: text !== ""
                    color: Theme.muted
                    font.pixelSize: Theme.sp(12)
                }
            }
        }
    }
    Label { objectName: "vpn-network-error"; text: root.errorText; visible: text !== ""; color: Theme.danger; Layout.fillWidth: true; Layout.leftMargin: 40; wrapMode: Text.Wrap }
}
