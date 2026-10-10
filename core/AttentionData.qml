pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather and today's calendar for every monitor's clock pill, refreshed every
// 15 minutes and at midnight. The center panel also keeps its browsed month here
// so reopening it is immediate.
QtObject {
    id: root
    property var forecast: null
    property string weatherError: ""
    readonly property bool weatherLoading: weatherQuery.running
    // Current month, independent of the month browsed in the panel.
    property var todayCloud: null
    property var cloud: null
    property string cloudMonth: ""
    property string cloudError: ""
    property double cloudCheckedAt: 0

    function refreshWeather() { weatherQuery.running = true; }
    function refreshToday() { todayQuery.running = true; }
    function refresh() { refreshWeather(); refreshToday(); }
    Component.onCompleted: refresh()

    property SystemClock dayClock: SystemClock { precision: SystemClock.Minutes }
    readonly property string currentDay: Qt.formatDate(dayClock.date, "yyyy-MM-dd")
    onCurrentDayChanged: Qt.callLater(refresh)
    property Timer timer: Timer { interval: 15 * 60 * 1000; running: true; repeat: true; onTriggered: root.refresh() }

    property Process todayQuery: Process {
        command: ["python3", Paths.file("attention/backend.py"), "calendar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.cloud) return;
                    root.todayCloud = result.cloud;
                    if (!root.cloud) {
                        root.cloud = result.cloud;
                        root.cloudMonth = Qt.formatDate(root.dayClock.date, "yyyy-MM");
                        root.cloudCheckedAt = Date.now();
                    }
                } catch (error) { /* Keep the last successful snapshot. */ }
            }
        }
    }
    property Process weatherQuery: Process {
        command: ["python3", Paths.file("attention/backend.py"), "weather"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.weatherError = result.error || "";
                    if (result.forecast) root.forecast = result.forecast;
                } catch (error) { root.weatherError = "Could not read the weather."; }
            }
        }
    }
}
