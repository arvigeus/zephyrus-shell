import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../widgets"

BarAction {
    id: root
    showToolTip: false
    leftPadding: 20; rightPadding: 20
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    property date today: clock.date
    property var cloud: AttentionData.todayCloud
    property int notificationCount: Attention.count
    readonly property string todayKey: Qt.formatDate(today, "yyyy-MM-dd")
    readonly property int todayTasks: cloud ? (cloud.tasks || []).filter(task => task.due === todayKey && !task.completed).length : 0
    readonly property int todayEvents: cloud ? (cloud.events || []).filter(event => event.date <= todayKey && (event.last_date || event.date) >= todayKey).length : 0
    readonly property bool hasIndicators: todayTasks > 0 || todayEvents > 0 || notificationCount > 0
    readonly property var weather: AttentionData.forecast ? AttentionData.forecast.current : null
    text: Qt.formatDateTime(today, "ddd, MMM d   ·   HH:mm")
    Accessible.description: [weather ? weather.description + ", " + Math.round(weather.temperature) + " degrees Celsius" : "",
        todayTasks ? todayTasks + " tasks today" : "", todayEvents ? todayEvents + " events today" : "",
        notificationCount ? notificationCount + " notifications" : ""].filter(value => !!value).join(", ")
    contentItem: RowLayout {
        spacing: 8
        Label { text: root.text }
        Label { visible: !!root.weather; text: "·" }
        Icon { visible: !!root.weather; name: root.weather ? root.weather.icon : "cloud"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
        Label { visible: !!root.weather; text: root.weather ? Math.round(root.weather.temperature) + "°C" : "" }
        Label { visible: root.hasIndicators; text: "·" }
        // Reload the corrected light SVGs across QML reloads, rather than
        // retaining an image cached before the indicator artwork was updated.
        Icon { objectName: "todayTasksIcon"; visible: root.todayTasks > 0; name: "list-todo"; cache: false; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
        Icon { objectName: "todayEventsIcon"; visible: root.todayEvents > 0; name: "calendar-days"; cache: false; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
        Icon { objectName: "notificationsIcon"; visible: root.notificationCount > 0; name: "bell"; cache: false; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
