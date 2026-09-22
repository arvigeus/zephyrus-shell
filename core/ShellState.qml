pragma Singleton
import QtQuick

QtObject {
    property string panel: ""
    property string monitor: ""
    property string pluginId: ""
    property var userProfile: ({})
    function openProfile(profile) { userProfile = profile; pluginId = ""; panel = "profile"; }
    function toggle(name, screenName) {
        if (!["left", "right", "center"].includes(name)) return;
        if (name === "left" && panel === "module") { close(); return; }
        const sameMonitor = screenName === undefined || monitor === screenName;
        if (screenName !== undefined) monitor = screenName;
        panel = panel === name && sameMonitor ? "" : name;
        pluginId = "";
    }
    function openPlugin(id) {
        if (!id) return;
        pluginId = id;
        panel = "module";
    }
    function backToSpaces() { pluginId = ""; panel = "left"; }
    function close() { panel = ""; pluginId = ""; }
}
