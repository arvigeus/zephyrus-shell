import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    objectName: "warp-network-row"
    spacing: 4
    property var connection: Warp
    readonly property bool connected: connection.state === "connected"
    readonly property string actionText: connection.enabled ? "Disconnect from Cloudflare WARP" : "Connect to Cloudflare WARP"


    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Action {
            objectName: "warp-network-icon"
            Layout.preferredWidth: 36
            implicitWidth: 36
            text: root.actionText
            toolTip: ""
            enabled: root.connection.available && !root.connection.transitioning
            opacity: root.connected || root.connection.transitioning ? 1 : 0.55
            onClicked: root.connection.toggle()
            contentItem: Item {
                implicitWidth: 19; implicitHeight: 19
                AppIcon {
                    objectName: "warp-network-artwork"
                    anchors.centerIn: parent
                    width: 23; height: 23
                    artwork: Warp.artwork
                }
            }
        }
        Action {
            objectName: "warp-network-toggle"
            Layout.fillWidth: true
            text: root.actionText
            enabled: root.connection.available && !root.connection.transitioning
            toolTip: ""
            onClicked: root.connection.toggle()
            contentItem: RowLayout {
                spacing: 6
                Label { objectName: "warp-network-name"; text: "Cloudflare WARP"; color: root.connected ? Theme.text : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { objectName: "warp-network-status"; text: root.connection.available ? root.connection.transitioning ? root.connection.label : "" : "Not installed"; visible: text !== ""; color: Theme.muted; font.pixelSize: Theme.sp(12) }
            }
        }
    }
    Label {
        objectName: "warp-network-error"
        visible: text !== ""
        text: root.connection.error
        color: Theme.danger
        Layout.fillWidth: true
        Layout.leftMargin: 40
        wrapMode: Text.Wrap
    }
}
