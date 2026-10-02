import QtQuick
import Quickshell
import "core"

ShellRoot {
    function compare(actual, expected) {
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            throw new Error("Expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
    }
    Timer {
        interval: 1; running: true
        onTriggered: {
            try {
                for (const test of [test_idle_switch_stops_resources_and_clears_payload,
                                   test_retained_owner_survives_desktop_and_other_monitor,
                                   test_hidden_release_preserves_foreground,
                                   test_navigation_is_opaque_and_cancelled_on_desktop,
                                   test_registry_removal_releases_all_owned_state,
                                   test_back_destroys_even_retained_module,
                                   test_clipboard_toggle_preserves_module_and_owner,
                                   test_removed_monitor_moves_module_ownership]) {
                    init(); test(); cleanup();
                }
                console.log("STATE PASS: lifetime, owner, opaque navigation, cancellation, registry removal");
            } catch (error) { console.error("STATE FAIL", error); }
            Qt.quit();
        }
    }

    function init() {
        for (const id of ShellState.runningPluginIds.slice()) ShellState.stopPlugin(id);
        ShellState.close();
        ShellState.monitor = "primary";
    }
    function cleanup() { init(); }

    function test_idle_switch_stops_resources_and_clears_payload() {
        ShellState.openPlugin("first", {title: "First"});
        ShellState.openPlugin("second");
        compare(ShellState.runningPluginIds, ["second"]);
        compare(ShellState.pendingPluginOpen, null);
        compare(ShellState.runningPluginMonitors.first, undefined);
    }
    function test_retained_owner_survives_desktop_and_other_monitor() {
        ShellState.openPlugin("player");
        ShellState.requestKeepRunning("player", true);
        ShellState.showDesktop();
        ShellState.monitor = "secondary";
        ShellState.openPlugin("other");
        ShellState.openPlugin("player");
        compare(ShellState.monitor, "primary");
        compare(ShellState.runningPluginIds, ["player"]);
        ShellState.close();
        compare(ShellState.runningPluginIds, []);
        compare(ShellState.retentionRequests.player, undefined);
    }
    function test_hidden_release_preserves_foreground() {
        ShellState.openPlugin("player");
        ShellState.requestKeepRunning("player", true);
        ShellState.openPlugin("other");
        ShellState.requestKeepRunning("player", false);
        compare(ShellState.runningPluginIds, ["other"]);
        compare(ShellState.pluginId, "other");
        compare(ShellState.panel, "module");
    }
    function test_navigation_is_opaque_and_cancelled_on_desktop() {
        const payload = {unrelatedToMedia: {id: 17}};
        ShellState.openPlugin("destination", payload);
        compare(ShellState.pendingPluginOpen.id, "destination");
        compare(ShellState.pendingPluginOpen.payload, payload);
        ShellState.requestKeepRunning("destination", true);
        ShellState.showDesktop();
        compare(ShellState.pendingPluginOpen, null);
        compare(ShellState.runningPluginIds, ["destination"]);
    }
    function test_registry_removal_releases_all_owned_state() {
        ShellState.openPlugin("player");
        ShellState.requestKeepRunning("player", true);
        ShellState.openPlugin("removed", {id: 3});
        ShellState.reconcilePlugins(["player"]);
        compare(ShellState.panel, "left");
        compare(ShellState.pendingPluginOpen, null);
        compare(ShellState.runningPluginIds, ["player"]);
        compare(ShellState.runningPluginMonitors.removed, undefined);
        ShellState.reconcilePlugins([]);
        compare(Object.keys(ShellState.retentionRequests), []);
        compare(Object.keys(ShellState.runningPluginMonitors), []);
    }
    function test_back_destroys_even_retained_module() {
        ShellState.openPlugin("player", {id: 1});
        ShellState.requestKeepRunning("player", true);
        ShellState.backToSpaces();
        compare(ShellState.panel, "left");
        compare(ShellState.runningPluginIds, []);
        compare(ShellState.pendingPluginOpen, null);
    }
    function test_removed_monitor_moves_module_ownership() {
        ShellState.openPlugin("player");
        ShellState.requestKeepRunning("player", true);
        ShellState.monitor = "secondary";
        ShellState.openPlugin("other");
        ShellState.reconcileScreens([]);
        compare(ShellState.pluginMonitor, "secondary");
        ShellState.reconcileScreens(["primary"]);
        compare(ShellState.monitor, "primary");
        compare(ShellState.pluginMonitor, "primary");
        compare(ShellState.runningPluginMonitors, {player: "primary", other: "primary"});
        compare(ShellState.retentionRequests.player, true);
        ShellState.showDesktop();
        compare(ShellState.runningPluginIds, ["player"]);
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
        compare(ShellState.runningPluginIds, ["first"]);
        ShellState.showDesktop();
        ShellState.toggle("clipboard", "secondary");
        ShellState.dismissPanel();
        compare(ShellState.panel, "");
        compare(ShellState.runningPluginIds, []);
    }
}
