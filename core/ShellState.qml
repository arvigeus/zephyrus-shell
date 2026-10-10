pragma Singleton
import QtQuick

QtObject {
    property string panel: ""
    property string monitor: ""
    property string moduleId: ""
    property string moduleMonitor: ""
    // Open modules own their resources until explicitly stopped from Spaces.
    property var runningModuleIds: []
    property var runningModuleMonitors: ({})
    property var userProfile: ({})
    // Opaque navigation payload; only the destination module interprets it.
    property var pendingModuleOpen: null
    function openProfile(profile) { userProfile = profile; panel = "profile"; }
    function toggle(name, screenName) {
        if (!["left", "right", "center", "clipboard"].includes(name)) return;
        const sameMonitor = screenName === undefined || monitor === screenName;
        if (screenName !== undefined) monitor = screenName;
        panel = panel === name && sameMonitor ? (moduleId ? "module" : "") : name;
    }
    function openModule(id, payload) {
        if (!id) return;
        pendingModuleOpen = payload === undefined ? null : {id: id, payload: payload};
        const owner = runningModuleMonitors[id] !== undefined ? runningModuleMonitors[id] : monitor;
        if (!runningModuleIds.includes(id)) runningModuleIds = runningModuleIds.concat([id]);
        runningModuleMonitors = Object.assign({}, runningModuleMonitors, {[id]: owner});
        monitor = owner;
        moduleId = id;
        moduleMonitor = monitor;
        panel = "module";
    }
    function showDesktop() {
        pendingModuleOpen = null;
        moduleId = ""; moduleMonitor = ""; panel = "";
    }
    function reconcileScreens(names) {
        // During output replacement there may briefly be no screen. Wait for
        // a real destination before moving ownership or closing any surface.
        if (!names.length) return;
        const fallback = names.includes(monitor) ? monitor : names[0];
        const owners = Object.assign({}, runningModuleMonitors);
        for (const id of runningModuleIds)
            if (!names.includes(owners[id])) owners[id] = fallback;
        runningModuleMonitors = owners;
        if (!names.includes(monitor)) monitor = fallback;
        if (moduleId) moduleMonitor = owners[moduleId];
    }
    function stopModule(id) {
        if (pendingModuleOpen && pendingModuleOpen.id === id) pendingModuleOpen = null;
        runningModuleIds = runningModuleIds.filter(value => value !== id);
        const owners = Object.assign({}, runningModuleMonitors);
        delete owners[id];
        runningModuleMonitors = owners;
        if (moduleId === id) {
            moduleId = ""; moduleMonitor = "";
            if (panel === "module") panel = "";
        }
    }
    function dismissPanel() {
        if (moduleId) monitor = moduleMonitor;
        panel = moduleId ? "module" : "";
    }
}
