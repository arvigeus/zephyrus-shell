import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"

Rectangle {
    id: root
    property string title
    property Component headerContent
    property string headerActionText: ""
    property bool headerActionEnabled: true
    signal headerActionRequested()
    property string subtitle
    property bool canGoBack: false
    property string backLabel: "Back"
    signal backRequested()
    default property alias content: body.data
    color: Theme.background; radius: 0
    border.color: Theme.border
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: ShellState.close()
    Rectangle { x: 20; y: 0; width: 44; height: 2; color: Theme.accent }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20; spacing: 16
        RowLayout {
            Layout.fillWidth: true
            IconButton { visible: root.canGoBack; iconName: "arrow-left"; text: root.backLabel; onClicked: root.backRequested() }
            Loader {
                visible: !!root.headerContent
                Layout.fillWidth: true
                sourceComponent: root.headerContent
            }
            ColumnLayout {
                visible: !root.headerContent
                Layout.fillWidth: true; spacing: 4
                Label { text: root.title; font.pixelSize: 23; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
                Label { text: root.subtitle; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true }
            }
            IconButton { visible: !!root.headerActionText; iconName: "refresh-cw"; text: root.headerActionText; enabled: root.headerActionEnabled; onClicked: root.headerActionRequested() }
            IconButton { iconName: "x"; text: "Close drawer"; onClicked: ShellState.close() }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
        Item { id: body; Layout.fillWidth: true; Layout.fillHeight: true }
    }
}
