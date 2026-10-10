import QtQuick
import "../core"

// Exists while any module is running; the live shell keeps one instance and
// reparents it to the screen that shows the current module.
Loader {
    id: root
    property bool readyToLoad: true
    visible: !!ShellState.moduleId
    active: ShellState.runningModuleIds.length > 0
    sourceComponent: ModuleOverlay { readyToLoad: root.readyToLoad }
}
