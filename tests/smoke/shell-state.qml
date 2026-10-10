import QtQuick
import Quickshell
import "../../core"

Scope {
    function compare(actual, expected) {
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            throw new Error("Expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
    }
    function reset() {
        for (const id of ShellState.runningModuleIds.slice()) ShellState.stopModule(id);
        ShellState.showDesktop();
        ShellState.monitor = "primary";
    }
    Timer {
        interval: 1; running: true
        onTriggered: {
            try {
                for (const test of [test_navigation_preserves_open_modules,
                                   test_owner_survives_desktop_and_other_monitor,
                                   test_hidden_close_preserves_foreground,
                                   test_navigation_is_opaque_and_cancelled_on_desktop,
                                   test_desktop_hides_without_stopping,
                                   test_close_from_drawer_keeps_drawer_open,
                                   test_clipboard_toggle_preserves_module_and_owner,
                                   test_removed_monitor_moves_module_ownership]) {
                    reset(); test(); reset();
                }
                console.log("STATE PASS: persistent lifetime, explicit stop, owner, opaque navigation, cancellation");
            } catch (error) { console.error("STATE FAIL", error); }
            Qt.quit();
        }
    }
    function test_navigation_preserves_open_modules() {
        ShellState.openModule("first", {title: "First"});
        ShellState.openModule("second");
        compare(ShellState.runningModuleIds, ["first", "second"]);
        compare(ShellState.pendingModuleOpen, null);
        compare(ShellState.runningModuleMonitors.first, "primary");
        ShellState.openModule("first");
        compare(ShellState.runningModuleIds, ["first", "second"]);
    }
    function test_owner_survives_desktop_and_other_monitor() {
        ShellState.openModule("player");
        ShellState.showDesktop();
        ShellState.monitor = "secondary";
        ShellState.openModule("other");
        ShellState.openModule("player");
        compare(ShellState.monitor, "primary");
        compare(ShellState.runningModuleIds, ["player", "other"]);
        ShellState.stopModule("player");
        compare(ShellState.runningModuleIds, ["other"]);
        compare(ShellState.runningModuleMonitors.player, undefined);
    }
    function test_hidden_close_preserves_foreground() {
        ShellState.openModule("player");
        ShellState.openModule("other");
        ShellState.stopModule("player");
        compare(ShellState.runningModuleIds, ["other"]);
        compare(ShellState.moduleId, "other");
        compare(ShellState.panel, "module");
    }
    function test_navigation_is_opaque_and_cancelled_on_desktop() {
        const payload = {unrelatedToMedia: {id: 17}};
        ShellState.openModule("destination", payload);
        compare(ShellState.pendingModuleOpen.id, "destination");
        compare(ShellState.pendingModuleOpen.payload, payload);
        ShellState.showDesktop();
        compare(ShellState.pendingModuleOpen, null);
        compare(ShellState.runningModuleIds, ["destination"]);
    }
    function test_desktop_hides_without_stopping() {
        ShellState.openModule("player", {id: 1});
        ShellState.showDesktop();
        compare(ShellState.pendingModuleOpen, null);
        compare(ShellState.panel, "");
        compare(ShellState.moduleId, "");
        compare(ShellState.runningModuleIds, ["player"]);
    }
    function test_close_from_drawer_keeps_drawer_open() {
        ShellState.openModule("first");
        ShellState.toggle("left");
        ShellState.stopModule("first");
        compare(ShellState.panel, "left");
        compare(ShellState.runningModuleIds, []);
        compare(ShellState.moduleMonitor, "");
    }
    function test_removed_monitor_moves_module_ownership() {
        ShellState.openModule("player");
        ShellState.monitor = "secondary";
        ShellState.openModule("other");
        ShellState.reconcileScreens([]);
        compare(ShellState.moduleMonitor, "secondary");
        ShellState.reconcileScreens(["primary"]);
        compare(ShellState.monitor, "primary");
        compare(ShellState.moduleMonitor, "primary");
        compare(ShellState.runningModuleMonitors, {player: "primary", other: "primary"});
        ShellState.showDesktop();
        compare(ShellState.runningModuleIds, ["player", "other"]);
    }
    function test_clipboard_toggle_preserves_module_and_owner() {
        ShellState.openModule("first");
        ShellState.toggle("clipboard", "primary");
        compare(ShellState.panel, "clipboard");
        compare(ShellState.runningModuleIds, ["first"]);
        ShellState.toggle("clipboard", "primary");
        compare(ShellState.panel, "module");
        ShellState.toggle("clipboard", "secondary");
        compare(ShellState.monitor, "secondary");
        compare(ShellState.moduleMonitor, "primary");
        ShellState.dismissPanel();
        compare(ShellState.panel, "module");
        compare(ShellState.monitor, "primary");
        ShellState.showDesktop();
        ShellState.toggle("clipboard", "secondary");
        ShellState.dismissPanel();
        compare(ShellState.panel, "");
        compare(ShellState.runningModuleIds, ["first"]);
    }
}
