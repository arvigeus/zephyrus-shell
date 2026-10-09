pragma Singleton
import QtQuick

QtObject {
    property string panel: ""
    property string monitor: ""
    property string pluginId: ""
    property string pluginMonitor: ""
    // Open modules own their resources until explicitly stopped from Spaces.
    property var runningPluginIds: []
    property var runningPluginMonitors: ({})
    property var userProfile: ({})
    // Opaque navigation payload; only the destination module interprets it.
    property var pendingPluginOpen: null
    function openProfile(profile) { userProfile = profile; panel = "profile"; }
    function toggle(name, screenName) {
        if (!["left", "right", "center", "clipboard"].includes(name)) return;
        const sameMonitor = screenName === undefined || monitor === screenName;
        if (screenName !== undefined) monitor = screenName;
        panel = panel === name && sameMonitor ? (pluginId ? "module" : "") : name;
    }
    function openPlugin(id, payload) {
        if (!id) return;
        pendingPluginOpen = payload === undefined ? null : {id: id, payload: payload};
        const owner = runningPluginMonitors[id] !== undefined ? runningPluginMonitors[id] : monitor;
        if (!runningPluginIds.includes(id)) runningPluginIds = runningPluginIds.concat([id]);
        runningPluginMonitors = Object.assign({}, runningPluginMonitors, {[id]: owner});
        monitor = owner;
        pluginId = id;
        pluginMonitor = monitor;
        panel = "module";
    }
    function showDesktop() {
        pendingPluginOpen = null;
        pluginId = ""; pluginMonitor = ""; panel = "";
    }
    function reconcileScreens(names) {
        // During output replacement there may briefly be no screen. Wait for
        // a real destination before moving ownership or closing any surface.
        if (!names.length) return;
        const fallback = names.includes(monitor) ? monitor : names[0];
        const owners = Object.assign({}, runningPluginMonitors);
        for (const id of runningPluginIds)
            if (!names.includes(owners[id])) owners[id] = fallback;
        runningPluginMonitors = owners;
        if (!names.includes(monitor)) monitor = fallback;
        if (pluginId) pluginMonitor = owners[pluginId];
    }
    function stopPlugin(id) {
        if (pendingPluginOpen && pendingPluginOpen.id === id) pendingPluginOpen = null;
        runningPluginIds = runningPluginIds.filter(value => value !== id);
        const owners = Object.assign({}, runningPluginMonitors);
        delete owners[id];
        runningPluginMonitors = owners;
        if (pluginId === id) {
            pluginId = ""; pluginMonitor = "";
            if (panel === "module") panel = "";
        }
    }
    function backToSpaces() {
        showDesktop();
        panel = "left";
    }
    function dismissPanel() {
        if (pluginId) monitor = pluginMonitor;
        panel = pluginId ? "module" : "";
    }
    function close() {
        showDesktop();
    }
}
