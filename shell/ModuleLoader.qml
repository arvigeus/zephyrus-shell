import QtQuick
import "../core"

Loader {
    id: root
    property bool readyToLoad: true
    active: !!ShellState.pluginId
    sourceComponent: ModuleOverlay { readyToLoad: root.readyToLoad }
}
