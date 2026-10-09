import QtQuick
import Quickshell
import "core"

ShellRoot {
    function compare(actual, expected) {
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            throw new Error("Expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
    }
    function reset() {
        for (const id of ShellState.runningPluginIds.slice()) ShellState.stopPlugin(id);
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
                                   test_back_and_escape_hide,
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
        ShellState.openPlugin("first", {title: "First"});
        ShellState.openPlugin("second");
        compare(ShellState.runningPluginIds, ["first", "second"]);
        compare(ShellState.pendingPluginOpen, null);
        compare(ShellState.runningPluginMonitors.first, "primary");
        ShellState.openPlugin("first");
        compare(ShellState.runningPluginIds, ["first", "second"]);
    }
    function test_owner_survives_desktop_and_other_monitor() {
        ShellState.openPlugin("player");
        ShellState.showDesktop();
        ShellState.monitor = "secondary";
        ShellState.openPlugin("other");
        ShellState.openPlugin("player");
        compare(ShellState.monitor, "primary");
        compare(ShellState.runningPluginIds, ["player", "other"]);
        ShellState.stopPlugin("player");
        compare(ShellState.runningPluginIds, ["other"]);
        compare(ShellState.runningPluginMonitors.player, undefined);
    }
    function test_hidden_close_preserves_foreground() {
        ShellState.openPlugin("player");
        ShellState.openPlugin("other");
        ShellState.stopPlugin("player");
        compare(ShellState.runningPluginIds, ["other"]);
        compare(ShellState.pluginId, "other");
        compare(ShellState.panel, "module");
    }
    function test_navigation_is_opaque_and_cancelled_on_desktop() {
        const payload = {unrelatedToMedia: {id: 17}};
        ShellState.openPlugin("destination", payload);
        compare(ShellState.pendingPluginOpen.id, "destination");
        compare(ShellState.pendingPluginOpen.payload, payload);
        ShellState.showDesktop();
        compare(ShellState.pendingPluginOpen, null);
        compare(ShellState.runningPluginIds, ["destination"]);
    }
    function test_back_and_escape_hide() {
        ShellState.openPlugin("player", {id: 1});
        ShellState.backToSpaces();
        compare(ShellState.panel, "left");
        compare(ShellState.runningPluginIds, ["player"]);
        compare(ShellState.pendingPluginOpen, null);
        ShellState.openPlugin("player");
        ShellState.close();
        compare(ShellState.panel, "");
        compare(ShellState.pluginId, "");
        compare(ShellState.runningPluginIds, ["player"]);
    }
    function test_close_from_drawer_keeps_drawer_open() {
        ShellState.openPlugin("first");
        ShellState.toggle("left");
        ShellState.stopPlugin("first");
        compare(ShellState.panel, "left");
        compare(ShellState.runningPluginIds, []);
        compare(ShellState.pluginMonitor, "");
    }
    function test_removed_monitor_moves_module_ownership() {
        ShellState.openPlugin("player");
        ShellState.monitor = "secondary";
        ShellState.openPlugin("other");
        ShellState.reconcileScreens([]);
        compare(ShellState.pluginMonitor, "secondary");
        ShellState.reconcileScreens(["primary"]);
        compare(ShellState.monitor, "primary");
        compare(ShellState.pluginMonitor, "primary");
        compare(ShellState.runningPluginMonitors, {player: "primary", other: "primary"});
        ShellState.showDesktop();
        compare(ShellState.runningPluginIds, ["player", "other"]);
    }
    function test_clipboard_toggle_preserves_module_and_owner() {
        ShellState.openPlugin("first");
        ShellState.toggle("clipboard", "primary");
        compare(ShellState.panel, "clipboard");
        compare(ShellState.runningPluginIds, ["first"]);
        ShellState.toggle("clipboard", "primary");
        compare(ShellState.panel, "module");
        ShellState.toggle("clipboard", "secondary");
        compare(ShellState.monitor, "secondary");
        compare(ShellState.pluginMonitor, "primary");
        ShellState.dismissPanel();
        compare(ShellState.panel, "module");
        compare(ShellState.monitor, "primary");
        ShellState.showDesktop();
        ShellState.toggle("clipboard", "secondary");
        ShellState.dismissPanel();
        compare(ShellState.panel, "");
        compare(ShellState.runningPluginIds, ["first"]);
    }
}
