import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

Item {
    id: root
    property date today: new Date()
    property var tasks: []
    property var events: []
    property int taskCount: tasks.length
    property string cloudState: "loading"
    property string cloudError: ""
    property bool cloudLoading: false
    property bool cloudStale: false
    property bool canAddTask: false
    property string view: "priority"
    signal completeTaskRequested(var task)
    signal addTaskRequested()
    signal editTaskRequested(var task)
    signal refreshRequested()

    readonly property string todayKey: Qt.formatDate(today, "yyyy-MM-dd")
    readonly property string dueSoon: Qt.formatDate(new Date(today.getFullYear(), today.getMonth(), today.getDate() + 7), "yyyy-MM-dd")
    readonly property var shownTasks: view === "all" ? tasks : tasks.filter(task => task.due && task.due <= dueSoon).slice(0, 2)
    readonly property var upcomingEvents: events.filter(event => new Date(event.end).getTime() > today.getTime())
    readonly property var shownEvents: view === "all" ? upcomingEvents : upcomingEvents.slice(0, 2)
    readonly property var notifications: Attention.notifications.values.slice().reverse()
    readonly property var shownNotifications: view === "all" ? notifications : notifications.slice(0, 2)

    function taskDetail(task) {
        const due = task.due ? task.due < todayKey ? "Overdue " + task.due : task.due === todayKey ? "Today" : task.due : "No due date";
        return due + " · " + task.list;
    }
    function eventDetail(event) {
        const when = new Date(event.start);
        return Qt.formatDate(when, "ddd, d MMM") + (event.all_day ? " · All day" : " · " + Qt.formatTime(when, "HH:mm")) + " · " + event.calendar;
    }
    onViewChanged: feed.contentY = 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 28
            Heading { text: "ATTENTION"; Layout.fillWidth: true }
            IconButton {
                iconName: "refresh-cw"
                iconSize: 16
                text: "Refresh Nextcloud"
                enabled: !root.cloudLoading
                onClicked: root.refreshRequested()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Action { text: "Priority"; highlighted: root.view === "priority"; onClicked: root.view = "priority" }
            Action { text: "All"; highlighted: root.view === "all"; onClicked: root.view = "all" }
            Item { Layout.fillWidth: true }
        }

        Flickable {
            id: feed
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: feedContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

            ColumnLayout {
                id: feedContent
                width: feed.width - 8
                spacing: 10

                Label { visible: root.cloudStale; text: "Showing saved Nextcloud data"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
                Label {
                    visible: root.cloudError !== "" && root.cloudState === "ready"
                    text: root.cloudError
                    Layout.fillWidth: true
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "TASKS"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11); font.letterSpacing: 1.4 }
                    IconButton {
                        iconName: "plus"
                        iconSize: 17
                        text: "Add task"
                        enabled: root.canAddTask
                        onClicked: root.addTaskRequested()
                    }
                    Item { Layout.fillWidth: true }
                    Label { visible: root.cloudState === "ready"; text: root.taskCount + " open"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
                }
                Label {
                    visible: root.cloudState !== "ready"
                    text: root.cloudError || (root.cloudState === "needs_password" ? "Add your Nextcloud app password to show tasks and events." : "Loading Nextcloud…")
                    Layout.fillWidth: true
                    color: Theme.muted
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Label {
                    visible: root.cloudState === "ready" && root.shownTasks.length === 0
                    text: root.taskCount && root.view === "priority" ? "No tasks due in the next 7 days." : "No open tasks."
                    color: Theme.muted
                }
                Repeater {
                    model: root.shownTasks
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Theme.controlRadius
                        color: Theme.surface
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            IconButton {
                                iconName: "square"
                                iconSize: 17
                                text: "Complete task"
                                enabled: modelData.actionable
                                onClicked: root.completeTaskRequested(modelData)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Label { text: modelData.summary; Layout.fillWidth: true }
                                Label { text: root.taskDetail(modelData); color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12); Layout.fillWidth: true }
                                TapHandler { onTapped: root.editTaskRequested(modelData) }
                            }
                            IconButton {
                                iconName: "chevron-right"
                                iconSize: 20
                                text: "Open task"
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 32
                                onClicked: root.editTaskRequested(modelData)
                            }
                        }
                    }
                }
                Label { text: "UPCOMING"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11); font.letterSpacing: 1.4; Layout.topMargin: 8 }
                Label { visible: root.cloudState === "ready" && root.shownEvents.length === 0; text: "Nothing upcoming."; color: Theme.muted }
                Repeater {
                    model: root.shownEvents
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Theme.controlRadius
                        color: Theme.surface
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            Rectangle { Layout.preferredWidth: 3; Layout.fillHeight: true; radius: 2; color: Theme.accent }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Label { text: modelData.summary; Layout.fillWidth: true }
                                Label { text: root.eventDetail(modelData); color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12); Layout.fillWidth: true }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Label {
                        text: "NOTIFICATIONS" + (root.view === "priority" && root.notifications.length > 2 ? " · " + root.notifications.length : "")
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.sp(11)
                        font.letterSpacing: 1.4
                        Layout.fillWidth: true
                    }
                    IconButton {
                        iconName: "bell-off"
                        iconSize: 18
                        text: Attention.quiet ? "Turn off Do not disturb" : "Turn on Do not disturb"
                        highlighted: Attention.quiet
                        onClicked: Attention.quiet = !Attention.quiet
                    }
                    IconButton {
                        iconName: "trash-2"
                        iconSize: 18
                        text: "Clear all notifications"
                        enabled: Attention.count > 0
                        onClicked: Attention.clear()
                    }
                }
                Label { visible: Attention.count === 0; text: "You're all caught up."; color: Theme.muted; Layout.fillWidth: true }
                Repeater {
                    model: root.shownNotifications
                    Rectangle {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: content.implicitHeight + 24
                        radius: Theme.controlRadius
                        color: Theme.surface
                        ColumnLayout {
                            id: content
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: card.modelData.summary; Layout.fillWidth: true; font.weight: Font.DemiBold; wrapMode: Text.Wrap; elide: Text.ElideNone }
                                IconButton { objectName: "dismissNotification:" + card.modelData.id; iconName: "x"; iconSize: 20; text: "Dismiss notification"; onClicked: card.modelData.dismiss() }
                            }
                            Label { text: card.modelData.body; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Theme.muted }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: card.modelData.actions
                                    Action { required property var modelData; text: modelData.text; onClicked: modelData.invoke() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
