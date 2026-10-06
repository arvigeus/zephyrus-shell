//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "core"
import "shell"
import "pictures"

ShellRoot {
    id: root
    WallpaperRuntime { id: wallpapers }
    // Module resources outlive individual output surfaces, including unplugging
    // the display where a retained player or worker was started.
    property ModuleLoader modules: ModuleLoader { screenName: "*"; readyToLoad: false; anchors.fill: parent }
    Component.onCompleted: {
        const ready = Profiles.loaded; const hardware = HardwareSnapshot.data;
        ThemeRuntime.start();
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { Qt.callLater(() => ShellState.reconcileScreens(Quickshell.screens.map(s => s.name))); }
    }
    IpcHandler {
        target: "shell"
        function toggle(panel: string): void {
            ShellState.toggle(panel, Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : undefined);
        }
        function close(): void { ShellState.close(); }
        function desktop(): void { ShellState.showDesktop(); }
        function openPlugin(id: string): void {
            if (!Modules.find(id)) return;
            if (Hyprland.focusedMonitor) ShellState.monitor = Hyprland.focusedMonitor.name;
            ShellState.openPlugin(id);
        }
        function reloadTheme(): void { Theme.refresh(); }
        function reloadSessionLock(): void { SessionLock.refresh(); }
        function lidClosed(): void {
            KeepAwake.setMode("off");
            ShellState.showDesktop();
        }
    }
    Variants {
        model: Quickshell.screens
        ShellScreen {
            required property var modelData
            screen: modelData
            sharedModules: root.modules
            externalWallpaper: wallpapers.externalScreens.includes(screenName)
        }
    }
}
