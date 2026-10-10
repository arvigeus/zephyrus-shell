//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "core"
import "shell"
import "modules/pictures"

ShellRoot {
    id: root
    WallpaperRuntime { id: wallpapers }
    // Owned by the root so running modules survive unplugging the screen that
    // shows them; ShellScreen reparents it to the current module's screen.
    property ModuleLoader modules: ModuleLoader { readyToLoad: false; anchors.fill: parent }
    Component.onCompleted: {
        // Singletons are lazy; Profiles must exist to apply battery-driven profiles.
        void Profiles.loaded;
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
        function close(): void { ShellState.showDesktop(); }
        function openModule(id: string): void {
            if (!Modules.find(id)) return;
            if (Hyprland.focusedMonitor) ShellState.monitor = Hyprland.focusedMonitor.name;
            ShellState.openModule(id);
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
            modules: root.modules
            externalWallpaper: wallpapers.externalScreens.includes(screenName)
        }
    }
}
