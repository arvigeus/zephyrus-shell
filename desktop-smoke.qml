import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 650; color: Theme.background
        Item {
            id: canvas; anchors.fill: parent
            ModuleLoader { id: modules; screenName: "*"; anchors.fill: parent }
        }
        Timer {
            interval: 100; repeat: true; running: true
            property int phase: 0
            property int ticks: 0
            property var rootModule: null
            function fail(message) { console.error("DESKTOP FAIL", message); stop(); Qt.quit(); }
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const result = find(child, name);
                    if (result) return result;
                }
                return null;
            }
            onTriggered: {
                if (++ticks > 120) {
                    fail("Timeout at phase " + phase + ": " + ShellState.pluginId + "/" + ShellState.runningPluginIds
                        + " " + (rootModule ? rootModule.errorText + "/" + rootModule.changing : "destroyed")); return;
                }
                if (phase === 0) {
                    if (!Plugins.find("clipboard")) return;
                    ShellState.monitor = "test";
                    ShellState.openPlugin("clipboard"); phase = 1;
                } else if (phase === 1) {
                    if (!modules.item || !modules.item.currentModule) return;
                    rootModule = modules.item.currentModule;
                    if (rootModule.loading) return;
                    if (rootModule.errorText || rootModule.entries.length !== 2) { fail("Real history did not load"); return; }
                    find(rootModule, "clipboardSearch").text = "first";
                    phase = 2;
                } else if (phase === 2) {
                    if (rootModule.filtered.length !== 1) { fail("Filtering did not match"); return; }
                    canvas.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/desktop-clipboard.png"))) { fail("Capture failed"); return; }
                        rootModule.act("delete", rootModule.filtered[0]); phase = 3;
                    }); phase = -1;
                } else if (phase === 3) {
                    if (rootModule.loading || rootModule.changing) return;
                    if (rootModule.entries.length !== 1) { fail("Deleted entry remained"); return; }
                    find(rootModule, "clipboardSearch").text = "";
                    rootModule.act("copy", rootModule.entries[0]); phase = 4;
                } else if (phase === 4 && !modules.item && !ShellState.pluginId) {
                    console.log("DESKTOP PASS: real cliphist, owned worker, search, delete, copy and module destruction");
                    stop(); Qt.quit();
                }
            }
        }
    }
}
