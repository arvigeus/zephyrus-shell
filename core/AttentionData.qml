pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var forecast: null
    property var cloud: null
    // Separate from the browsed month so navigating the calendar cannot change
    // today's bar indicators. One snapshot is shared by all monitor pills.
    property var todayCloud: null
    property string todayCloudMonth: ""
    property SystemClock dayClock: SystemClock { precision: SystemClock.Minutes }
    readonly property string currentDay: Qt.formatDate(dayClock.date, "yyyy-MM-dd")
    onCurrentDayChanged: Qt.callLater(() => root.refreshToday())
    property string cloudMonth: ""
    property string weatherError: ""
    property string cloudError: ""
    property double weatherCheckedAt: 0
    property double cloudCheckedAt: 0
    readonly property bool weatherLoading: weatherQuery.running
    function refreshWeather(force) {
        if (weatherLoading || (!force && weatherCheckedAt && Date.now() - weatherCheckedAt < 15 * 60 * 1000)) return;
        weatherQuery.running = true;
    }
    function refreshToday() { if (!todayQuery.running) todayQuery.running = true; }
    Component.onCompleted: { refreshWeather(); refreshToday(); }
    property Timer todayTimer: Timer {
        interval: 15 * 60 * 1000; running: true; repeat: true
        onTriggered: root.refreshToday()
    }
    property Process todayQuery: Process {
        command: ["python3", Paths.file("scripts/attention-summary.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.cloud) {
                        root.todayCloud = result.cloud;
                        root.todayCloudMonth = result.month;
                        if (!root.cloud) {
                            root.cloud = result.cloud;
                            root.cloudMonth = result.month;
                            root.cloudCheckedAt = Date.now();
                        }
                    }
                } catch (error) { /* Keep the last successful snapshot. */ }
            }
        }
    }
    property Timer weatherTimer: Timer {
        interval: 15 * 60 * 1000; running: true; repeat: true
        onTriggered: root.refreshWeather()
    }
    property Process weatherQuery: Process {
        command: ["python3", Paths.file("scripts/weather.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.weatherError = result.error || "";
                    if (result.forecast) root.forecast = result.forecast;
                } catch (error) { root.weatherError = "Could not read the weather."; }
                root.weatherCheckedAt = Date.now();
            }
        }
    }
}
