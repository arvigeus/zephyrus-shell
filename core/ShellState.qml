pragma Singleton
import QtQuick

QtObject {
    property string panel: ""
    property string monitor: ""
    property string pluginId: ""
    property var userProfile: ({})
    function openProfile(profile) { userProfile = profile; panel = "profile"; }
    function toggle(name, screenName) {
        if (!["left", "right", "center"].includes(name)) return;
        if (name === "left" && pluginId) { close(); return; }
        const sameMonitor = screenName === undefined || monitor === screenName;
        if (screenName !== undefined) monitor = screenName;
        panel = panel === name && sameMonitor ? (pluginId ? "module" : "") : name;
    }
    function openPlugin(id) {
        if (!id) return;
        pluginId = id;
        panel = "module";
    }
    function backToSpaces() { pluginId = ""; panel = "left"; }
    function dismissPanel() { panel = pluginId ? "module" : ""; }
    function close() { panel = ""; pluginId = ""; }
}
