pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property var forecast: null
    property var cloud: null
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
    Component.onCompleted: refreshWeather()
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
