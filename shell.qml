import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "shell"

ShellRoot {
    Component.onCompleted: { const ready = Profiles.loaded; const hardware = HardwareSnapshot.data; }
    IpcHandler {
        target: "shell"
        function toggle(panel: string): void { ShellState.toggle(panel); }
        function close(): void { ShellState.close(); }
        function reloadPlugins(): void { Plugins.reload(); }
    }
    Variants {
        model: Quickshell.screens
        ShellScreen { required property var modelData; screen: modelData }
    }
}
