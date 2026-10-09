import QtQuick
import Quickshell
import "core"
import "shell"
import "clipboard"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 900; implicitHeight: 650; color: Theme.background
        Item {
            id: canvas; anchors.fill: parent
            ModuleLoader { id: modules; screenName: "*"; anchors.fill: parent }
        }
        ClipboardButton { id: button; x: 750; y: Theme.pillVerticalPadding; screenName: "test" }
        ClipboardPopup { id: popup; barWindow: window; screenName: "test"; readyToOpen: false }
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
                    if (!Modules.find("apps")) return;
                    if (Modules.find("clipboard")) { fail("Clipboard is still a module"); return; }
                    ShellState.monitor = "test";
                    ShellState.openPlugin("apps"); phase = 10;
                } else if (phase === 10) {
                    if (!modules.item || !modules.item.currentModule) return;
                    button.clicked(); phase = 11;
                } else if (phase === 11) {
                    if (popup.visible || popup.panel) { fail("Popover opened before drawer finished closing"); return; }
                    popup.readyToOpen = true; phase = 1;
                } else if (phase === 1) {
                    if (!popup.panel) return;
                    rootModule = popup.panel;
                    if (rootModule.loading) return;
                    if (rootModule.errorText || rootModule.entries.length !== 2) { fail("Real history did not load"); return; }
                    find(rootModule, "clipboardSearch").text = "first";
                    phase = 2;
                } else if (phase === 2) {
                    if (rootModule.filtered.length !== 1) { fail("Filtering did not match"); return; }
                    rootModule.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/desktop-clipboard.png"))) { fail("Capture failed"); return; }
                        rootModule.act("delete", rootModule.filtered[0]); phase = 3;
                    }); phase = -1;
                } else if (phase === 3) {
                    if (rootModule.loading || rootModule.changing) return;
                    if (rootModule.entries.length !== 1) { fail("Deleted entry remained"); return; }
                    find(rootModule, "clipboardSearch").text = "";
                    rootModule.act("copy", rootModule.entries[0]); phase = 4;
                } else if (phase === 4 && !popup.panel) {
                    if (!modules.item || ShellState.pluginId !== "apps" || ShellState.panel !== "module") {
                        fail("Copy discarded the underlying module"); return;
                    }
                    button.clicked(); phase = 5;
                } else if (phase === 5 && popup.panel && !popup.panel.loading) {
                    if (popup.panel.entries.length !== 1) { fail("Reopening did not refresh history"); return; }
                    button.clicked(); phase = 6;
                } else if (phase === 6 && !popup.panel) {
                    if (ShellState.panel !== "module") { fail("Toggle did not return to the module"); return; }
                    button.clicked(); phase = 7;
                } else if (phase === 7 && popup.panel && !popup.panel.loading) {
                    popup.panel.act("clear", null); phase = 8;
                } else if (phase === 8 && popup.panel && !popup.panel.loading && !popup.panel.changing) {
                    if (popup.panel.entries.length) { fail("History did not clear"); return; }
                    popup.panel.closeRequested(); phase = 9;
                } else if (phase === 9 && !popup.panel) {
                    ShellState.stopPlugin("apps");
                    console.log("DESKTOP PASS: real clipboard popover, deferred opening, search, delete, copy, toggle, clear and owned worker release");
                    stop(); Qt.quit();
                }
            }
        }
    }
}
