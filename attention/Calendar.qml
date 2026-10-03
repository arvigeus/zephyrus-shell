import QtQuick
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    property date selectedDate: today
    property var events: []
    property string cloudState: "loading"
    property string cloudError: ""
    property bool canAddEvent: false
    signal addEventRequested(date day)
    signal editEventRequested(var event)
    readonly property int offset: (month.getDay() + 6) % 7
    Layout.fillWidth: true
    function moveMonth(delta) {
        month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
        selectedDate = new Date(month.getFullYear(), month.getMonth(), 1);
    }
    function moveYear(delta) {
        month = new Date(month.getFullYear() + delta, month.getMonth(), 1);
        selectedDate = new Date(month.getFullYear(), month.getMonth(), 1);
    }
    function dayKey(day) { return Qt.formatDate(day, "yyyy-MM-dd"); }
    function eventsFor(day) {
        const key = dayKey(day);
        return events.filter(event => event.date <= key && (event.last_date || event.date) >= key);
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 2
        Action { iconName: "chevron-left"; Accessible.name: "Previous month"; Layout.preferredWidth: 28; Layout.preferredHeight: 34; onClicked: root.moveMonth(-1) }
        Label { text: Qt.formatDate(root.month, "MMMM"); font.family: Theme.font; font.pixelSize: Theme.sp(18) }
        Action { iconName: "chevron-right"; Accessible.name: "Next month"; Layout.preferredWidth: 28; Layout.preferredHeight: 34; onClicked: root.moveMonth(1) }
        Item { Layout.fillWidth: true }
        Action { iconName: "chevron-left"; Accessible.name: "Previous year"; Layout.preferredWidth: 28; Layout.preferredHeight: 34; onClicked: root.moveYear(-1) }
        Label { text: root.month.getFullYear(); font.family: Theme.font; font.pixelSize: Theme.sp(18) }
        Action { iconName: "chevron-right"; Accessible.name: "Next year"; Layout.preferredWidth: 28; Layout.preferredHeight: 34; onClicked: root.moveYear(1) }
    }
    GridLayout {
        columns: 7; rowSpacing: 3; columnSpacing: 3; Layout.fillWidth: true
        Repeater {
            model: ["M", "T", "W", "T", "F", "S", "S"]
            Label { required property string modelData; text: modelData; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredHeight: 26 }
        }
        Repeater {
            model: 42
            Rectangle {
                id: cell
                required property int index
                readonly property date day: new Date(root.month.getFullYear(), root.month.getMonth(), index - root.offset + 1)
                readonly property bool isToday: day.toDateString() === root.today.toDateString()
                readonly property bool isSelected: day.toDateString() === root.selectedDate.toDateString()
                Layout.fillWidth: true; Layout.preferredHeight: 32
                radius: Theme.controlRadius; color: isToday ? Theme.accent : "transparent"
                border.color: isSelected && !isToday ? Theme.accent : "transparent"
                Label { anchors.centerIn: parent; text: parent.day.getDate(); color: parent.isToday ? Theme.background : parent.day.getMonth() === root.month.getMonth() ? Theme.text : Theme.muted; opacity: parent.day.getMonth() === root.month.getMonth() ? 1 : 0.4 }
                Rectangle {
                    visible: root.eventsFor(cell.day).length > 0
                    width: 4; height: 4; radius: 2
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
                    color: cell.isToday ? Theme.background : Theme.accent
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.selectedDate = cell.day;
                        if (cell.day.getMonth() !== root.month.getMonth())
                            root.month = new Date(cell.day.getFullYear(), cell.day.getMonth(), 1);
                    }
                }
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 8 }
    RowLayout {
        Layout.fillWidth: true
        Label {
            text: Qt.formatDate(root.selectedDate, "dddd, d MMMM")
            Layout.fillWidth: true
            font.weight: Font.DemiBold
        }
        IconButton {
            iconName: "plus"
            iconSize: 18
            text: "Add event on selected day"
            enabled: root.canAddEvent
            onClicked: root.addEventRequested(root.selectedDate)
        }
    }
    Label {
        visible: root.eventsFor(root.selectedDate).length === 0
        text: root.cloudState === "ready" ? "No events" : root.cloudError || (root.cloudState === "needs_password" ? "Add your Nextcloud app password to show events." : "Loading calendar…")
        Layout.fillWidth: true
        color: Theme.muted
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    Repeater {
        model: root.eventsFor(root.selectedDate).slice(0, 3)
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 24; radius: 2; color: Theme.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: modelData.summary; Layout.fillWidth: true }
                Label { text: (modelData.all_day ? "All day" : Qt.formatTime(new Date(modelData.start), "HH:mm")) + " · " + modelData.calendar; Layout.fillWidth: true; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
                TapHandler { onTapped: root.editEventRequested(modelData) }
            }
            Action {
                iconName: "chevron-right"
                Accessible.name: "Open event"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 32
                onClicked: root.editEventRequested(modelData)
            }
        }
    }
}
