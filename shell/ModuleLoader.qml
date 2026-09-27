import QtQuick
import "../core"

Loader {
    id: root
    property bool readyToLoad: true
    property string screenName: ""
    active: !!ShellState.pluginId || ShellState.runningPluginIds.length > 0
    sourceComponent: ModuleOverlay { readyToLoad: root.readyToLoad; screenName: root.screenName }
}
