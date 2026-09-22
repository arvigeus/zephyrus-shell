import QtQuick
import QtQuick.Layouts
import "../drawers"
import "../core"

DrawerFrame {
    id: root
    title: "At a glance"
    subtitle: Qt.formatDateTime(new Date(), "dddd, d MMMM")
    GridLayout {
        anchors.fill: parent; columnSpacing: 28; rowSpacing: 16
        columns: root.width >= 700 ? 2 : 1
        Calendar { Layout.preferredWidth: 350; Layout.maximumWidth: root.width >= 700 ? 350 : Infinity; Layout.alignment: Qt.AlignTop }
        NotificationList { Layout.fillWidth: true; Layout.fillHeight: true }
    }
}
