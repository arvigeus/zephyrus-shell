pragma Singleton
import QtQuick

QtObject {
    property string panel: ""
    property string monitor: ""
    property string pluginId: ""
    property string pluginMonitor: ""
    // A retained module owns its player and worker while another space is shown.
    property var runningPluginIds: []
    property var runningPluginMonitors: ({})
    property var userProfile: ({})
    function openProfile(profile) { userProfile = profile; panel = "profile"; }
    function toggle(name, screenName) {
        if (!["left", "right", "center"].includes(name)) return;
        const sameMonitor = screenName === undefined || monitor === screenName;
        if (screenName !== undefined) monitor = screenName;
        panel = panel === name && sameMonitor ? (pluginId ? "module" : "") : name;
    }
    function openPlugin(id, keepRunning) {
        if (!id) return;
        if (keepRunning || runningPluginIds.includes(id)) {
            const owner = runningPluginMonitors[id] !== undefined ? runningPluginMonitors[id] : monitor;
            if (!runningPluginIds.includes(id)) runningPluginIds = runningPluginIds.concat([id]);
            runningPluginMonitors = Object.assign({}, runningPluginMonitors, {[id]: owner});
            monitor = owner;
        }
        pluginId = id;
        pluginMonitor = monitor;
        panel = "module";
    }
    function showDesktop() { pluginId = ""; pluginMonitor = ""; panel = ""; }
    function stopPlugin(id) {
        runningPluginIds = runningPluginIds.filter(value => value !== id);
        const owners = Object.assign({}, runningPluginMonitors);
        delete owners[id];
        runningPluginMonitors = owners;
        if (pluginId === id) { pluginId = ""; pluginMonitor = ""; panel = ""; }
    }
    function backToSpaces() {
        if (pluginId) stopPlugin(pluginId);
        pluginId = ""; pluginMonitor = ""; panel = "left";
    }
    function dismissPanel() {
        if (pluginId) monitor = pluginMonitor;
        panel = pluginId ? "module" : "";
    }
    function close() {
        if (pluginId) stopPlugin(pluginId);
        panel = ""; pluginId = ""; pluginMonitor = "";
    }
}
