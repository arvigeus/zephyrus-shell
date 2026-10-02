import QtQuick
import "../core"

Loader {
    id: root
    property bool readyToLoad: true
    property string screenName: ""
    active: screenName === "*" ? ShellState.runningPluginIds.length > 0
        : ShellState.runningPluginIds.some(id => ShellState.runningPluginMonitors[id] === screenName)
    sourceComponent: ModuleOverlay { readyToLoad: root.readyToLoad; screenName: root.screenName }
}
