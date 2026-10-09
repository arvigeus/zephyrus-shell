//@ pragma UseQApplication
// Real compositor actions only touch this harness's own test window.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "core"
import "shell"

ShellRoot {
    id: root
    property ModuleLoader modules: ModuleLoader { screenName: "*"; readyToLoad: false; anchors.fill: parent }
    Connections {
        target: Quickshell
        function onScreensChanged() { Qt.callLater(() => ShellState.reconcileScreens(Quickshell.screens.map(s => s.name))); }
    }
    Process { id: removeMonitor; command: ["hyprctl", "output", "remove", "ZEPHYRUS-TEST"] }
    Variants {
        model: Quickshell.screens
        ShellScreen { required property var modelData; screen: modelData; sharedModules: root.modules }
    }
    FloatingWindow {
        id: testWindow
        title: "Zephyrus window controls test"
        implicitWidth: 640; implicitHeight: 480
        color: Theme.background
        Item { id: anchorButton; width: 34; height: 34 }
        WindowMenu { id: menu; barWindow: testWindow }
    }
    // Keep an exclusive surface alive beyond the old 50ms activation delay.
    // Its release must restore real Qt keyboard focus, not just activated flags.
    PanelWindow {
        id: delayedFocus
        visible: false
        anchors { top: true; left: true }
        implicitWidth: 1; implicitHeight: 1
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zephyrus-window-focus-test"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        mask: Region {}
    }
    Timer { id: releaseFocus; interval: 300; onTriggered: delayedFocus.visible = false }
    Timer {
        id: check
        interval: 160; repeat: true; running: true
        property int step: 0
        property int ticks: 0
        property var target: null
        property real halfWidth: 0
        property real quarterWidth: 0
        property var retainedModule: null
        function advance() { step++; ticks = 0; }
        function fail(message) { console.error("WINDOW CONTROLS FAIL", message); Qt.quit(); }
        onTriggered: {
            if (++ticks > 70) { fail("Timeout at step " + step); return; }
            target = WindowList.windows.find(w => w.title === testWindow.title) || null;
            if (!target && step < 15) return;
            const client = target ? WindowList.clientFor(target) : null;
            if (step === 0) {
                if (!client || !Modules.find("apps")) return;
                ShellState.openPlugin("apps"); advance();
            } else if (step === 1) {
                if (!root.modules.item || !root.modules.item.currentModule) return;
                delayedFocus.visible = true; step = 30; ticks = 0;
            } else if (step === 30) {
                if (!delayedFocus.contentItem.Window.active) return;
                WindowList.activate(target); releaseFocus.restart(); step = 2; ticks = 0;
            } else if (step === 2) {
                if (ShellState.pluginId || !target.activated || !testWindow.contentItem.Window.active) return;
                WindowList.moveToMonitor(target, "ZEPHYRUS-TEST"); step = 20; ticks = 0;
            } else if (step === 20 && ticks > 5) {
                const monitor = WindowList.monitors.find(m => m.name === "ZEPHYRUS-TEST");
                if (!monitor || client.lastIpcObject.monitor !== monitor.id) { fail("Single-window monitor unavailable"); return; }
                const tiled = Hyprland.toplevels.values.filter(w => w.lastIpcObject.mapped && !w.lastIpcObject.floating
                    && !w.lastIpcObject.hidden && w.lastIpcObject.workspace.id === client.lastIpcObject.workspace.id);
                if (tiled.length !== 1) { fail("Sizing fixture is not a single-window workspace"); return; }
                WindowList.setWidth(target, 0.5); advance();
                step = 3;
            } else if (step === 3 && ticks > 5) {
                halfWidth = client.lastIpcObject.size[0];
                WindowList.setWidth(target, 0.25); advance();
            } else if (step === 4 && ticks > 5) {
                quarterWidth = client.lastIpcObject.size[0];
                if (quarterWidth >= halfWidth * 0.75) { fail("Quarter did not shrink the selected window"); return; }
                WindowList.setWidth(target, 0.75); step = 21; ticks = 0;
            } else if (step === 21 && ticks > 5) {
                const width = client.lastIpcObject.size[0];
                if (width < halfWidth * 1.35 || width > halfWidth * 1.65) { fail("Three-quarter size did not hold with a single window"); return; }
                WindowList.setWidth(target, 1); step = 5; ticks = 0;
            } else if (step === 5 && ticks > 5) {
                if (client.lastIpcObject.size[0] < halfWidth * 1.6) { fail("Full did not expand the selected window"); return; }
                WindowList.toggleFloating(target); advance();
            } else if (step === 6 && ticks > 4) {
                if (!client.lastIpcObject.floating) { fail("Float did not affect the selected window"); return; }
                WindowList.setWidth(target, 0.5); advance();
            } else if (step === 7 && ticks > 5) {
                if (Math.abs(client.lastIpcObject.size[0] - halfWidth) > 80) { fail("Floating half size is inconsistent"); return; }
                menu.openFor(target, anchorButton); advance();
            } else if (step === 8 && ticks > 3) {
                if (!menu.visible) { fail("Window menu did not open"); return; }
                stop();
                menu.panel.grabToImage(result => {
                    if (!result.saveToFile(Paths.file("tests/artifacts/window-menu.png"))) { check.fail("Menu capture failed"); return; }
                    menu.visible = false;
                    WindowList.toggleFloating(check.target); check.advance(); check.start();
                });
            } else if (step === 9 && ticks > 4) {
                if (client.lastIpcObject.floating) { fail("Tile did not affect the selected window"); return; }
                const other = WindowList.monitors.find(m => m.name !== "ZEPHYRUS-TEST");
                if (!other || !WindowList.moveToMonitor(target, other.name)) { fail("Other monitor unavailable"); return; }
                step = 22; ticks = 0;
            } else if (step === 22 && ticks > 5) {
                const monitor = WindowList.monitors.find(m => m.name === "ZEPHYRUS-TEST");
                if (client.lastIpcObject.monitor === monitor.id) { fail("Monitor move did not leave the test output"); return; }
                if (!WindowList.moveToMonitor(target, "ZEPHYRUS-TEST")) { fail("Test monitor unavailable"); return; }
                step = 10; ticks = 0;
            } else if (step === 10 && ticks > 5) {
                const monitor = WindowList.monitors.find(m => m.name === "ZEPHYRUS-TEST");
                if (!monitor || client.lastIpcObject.monitor !== monitor.id) { fail("Monitor move did not transfer the selected window"); return; }
                ShellState.monitor = monitor.name;
                ShellState.openPlugin("apps"); advance();
            } else if (step === 11) {
                if (!root.modules.item || !root.modules.item.currentModule) return;
                retainedModule = root.modules.item.currentModule;
                removeMonitor.running = true; advance();
            } else if (step === 12 && ticks > 5) {
                if (WindowList.monitors.some(m => m.name === "ZEPHYRUS-TEST")) return;
                if (!WindowList.monitors.some(m => m.id === client.lastIpcObject.monitor)) { fail("Removed monitor stranded the window"); return; }
                if (!root.modules.item || root.modules.item.currentModule !== retainedModule
                    || ShellState.pluginMonitor === "ZEPHYRUS-TEST") { fail("Monitor removal recreated or stranded the module"); return; }
                WindowList.activate(target); advance();
            } else if (step === 13 && ticks > 3) {
                if (!target.activated || ShellState.pluginId || !ShellState.runningPluginIds.includes("apps")) {
                    fail("Activation did not preserve retained resources: " + JSON.stringify({activated:target.activated, pluginId:ShellState.pluginId, running:ShellState.runningPluginIds})); return;
                }
                ShellState.stopPlugin("apps"); target.close(); step = 15; ticks = 0;
            } else if (step === 15 && !target && !root.modules.item) {
                console.log("WINDOW CONTROLS PASS: module dismissal, delayed exclusive-layer release, native keyboard focus, single-window 25/50/75/100% sizes, float/tile, popup, monitor transfer/removal, retained module migration, close");
                Qt.quit();
            }
        }
    }
}
