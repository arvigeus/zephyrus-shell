import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../widgets"

Rectangle {
    id: root
    readonly property var forecast: AttentionData.forecast
    readonly property var cloud: AttentionData.cloud || ({state: "loading", events: [], tasks: [], calendars: []})
    readonly property string weatherError: AttentionData.weatherError
    readonly property string cloudError: AttentionData.cloudError
    readonly property bool weatherLoading: AttentionData.weatherLoading
    property bool cloudLoading: false
    property int cloudGeneration: 0
    property string compactPage: "calendar"
    readonly property bool compactLayout: width < 990
    color: Theme.background
    border.color: Theme.border
    focus: true

    Component.onCompleted: forceActiveFocus()
    function dismiss() {
        if (editor.opened) editor.close();
        else ShellState.dismissPanel();
    }
    Keys.onEscapePressed: root.dismiss()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    Worker {
        id: service
        backend: "attention/backend.py"
        serviceName: "Attention"
        timeout: 45000
        onReady: Qt.callLater(() => {
            const now = Date.now();
            const today = Qt.formatDate(clock.date, "yyyy-MM-dd");
            if (!AttentionData.weatherCheckedAt || now - AttentionData.weatherCheckedAt >= 15 * 60 * 1000
                    || (root.forecast && (!Array.isArray(root.forecast.hours)
                        || root.forecast.days.some(day => !day.summary_source)))
                    || (root.forecast && root.forecast.days && root.forecast.days[0].date !== today))
                root.refreshWeather();
            if (!AttentionData.cloudCheckedAt || AttentionData.cloudMonth !== root.monthKey()
                    || now - AttentionData.cloudCheckedAt >= 15 * 60 * 1000)
                root.refreshCloud();
        })
    }

    function monthKey() { return Qt.formatDate(calendarPane.month, "yyyy-MM"); }
    function refreshWeather() { AttentionData.refreshWeather(true); }
    function refreshCloud(force) {
        const generation = ++cloudGeneration;
        const month = calendarPane.month;
        const start = Qt.formatDate(new Date(month.getFullYear(), month.getMonth(), 1), "yyyy-MM-dd");
        const end = Qt.formatDate(new Date(month.getFullYear(), month.getMonth() + 1, 1), "yyyy-MM-dd");
        cloudLoading = true;
        service.request("nextcloud", {start: start, end: end, refresh: !!force}, (result, error) => {
            if (generation !== cloudGeneration) return;
            cloudLoading = false;
            AttentionData.cloudError = error;
            AttentionData.cloudCheckedAt = Date.now();
            if (result) {
                AttentionData.cloudMonth = Qt.formatDate(month, "yyyy-MM");
                AttentionData.cloud = result;
                if (Qt.formatDate(calendarPane.month, "yyyy-MM") !== Qt.formatDate(month, "yyyy-MM")) {
                    Qt.callLater(() => root.refreshCloud());
                    return;
                }
                if (result.refresh_due && !force) Qt.callLater(() => root.refreshCloud(true));
            }
        });
    }
    function completeTask(task) {
        service.request("complete_task", {task: {href: task.href, etag: task.etag}}, (result, error) => {
            if (error) AttentionData.cloudError = error;
            else refreshCloud(true);
        });
    }
    function saveEntry(kind, entry) {
        editor.busy = true;
        service.request("save_item", {kind: kind, entry: entry}, (result, error) => {
            editor.busy = false;
            if (error) {
                editor.error = error;
                return;
            }
            editor.opened = false;
            refreshCloud(true);
        });
    }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: true; onTriggered: root.refreshWeather() }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: true; onTriggered: root.refreshCloud() }

    Rectangle { x: 20; y: 0; width: 44; height: 2; color: Theme.accent }

    RowLayout {
        visible: root.compactLayout
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 56; rightMargin: 56; topMargin: 26 }
        spacing: 4
        Action { text: "Weather"; highlighted: root.compactPage === "weather"; Layout.fillWidth: true; onClicked: root.compactPage = "weather" }
        Action { text: "Calendar"; highlighted: root.compactPage === "calendar"; Layout.fillWidth: true; onClicked: root.compactPage = "calendar" }
        Action { text: "Attention"; highlighted: root.compactPage === "attention"; Layout.fillWidth: true; onClicked: root.compactPage = "attention" }
    }

    GridLayout {
        id: columns
        anchors.fill: parent
        anchors.margins: 24
        anchors.topMargin: root.compactLayout ? 82 : 28
        columns: root.compactLayout ? 1 : 3
        columnSpacing: 22
        rowSpacing: 24
        readonly property real columnWidth: (width - (columns.columns - 1) * columnSpacing) / columns.columns

            WeatherPanel {
                id: weatherPane
                visible: !root.compactLayout || root.compactPage === "weather"
                narrow: root.compactLayout
                forecast: root.forecast
                loading: root.weatherLoading
                error: root.weatherError
                onRefreshRequested: root.refreshWeather()
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: columns.columnWidth
                Layout.fillWidth: true
            }
            Calendar {
                id: calendarPane
                visible: !root.compactLayout || root.compactPage === "calendar"
                today: clock.date
                events: root.cloud.events || []
                cloudState: root.cloud.state || "loading"
                cloudError: root.cloudError
                canAddEvent: (root.cloud.calendars || []).some(item => item.writable && item.events_enabled && item.components.includes("VEVENT"))
                onAddEventRequested: day => editor.begin("VEVENT", null, Qt.formatDate(day, "yyyy-MM-dd"), root.cloud.calendars || [])
                onEditEventRequested: event => editor.begin("VEVENT", event, event.date, root.cloud.calendars || [])
                onMonthChanged: if (root.cloud.state === "ready") root.refreshCloud()
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: columns.columnWidth
                Layout.fillWidth: true
            }
            NotificationList {
                visible: !root.compactLayout || root.compactPage === "attention"
                today: clock.date
                tasks: root.cloud.tasks || []
                taskCount: root.cloud.task_count || 0
                events: root.cloud.events || []
                cloudState: root.cloud.state || "loading"
                cloudError: root.cloudError
                cloudLoading: root.cloudLoading
                cloudStale: !!root.cloud.stale
                canAddTask: (root.cloud.calendars || []).some(item => item.writable && item.tasks_enabled && item.components.includes("VTODO"))
                onAddTaskRequested: editor.begin("VTODO", null, "", root.cloud.calendars || [])
                onEditTaskRequested: task => editor.begin("VTODO", task, "", root.cloud.calendars || [])
                onCompleteTaskRequested: task => root.completeTask(task)
                onRefreshRequested: root.refreshCloud(true)
                Layout.preferredWidth: columns.columnWidth
                Layout.fillHeight: true
                Layout.fillWidth: true
            }
    }
    EntryEditor {
        id: editor
        z: 10
        anchors.fill: parent
        onSaveRequested: (kind, entry) => root.saveEntry(kind, entry)
    }
}
