import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1280; implicitHeight: 800
        color: Theme.background
        ModuleLoader {
            id: overlay; anchors.fill: parent; screenName: "primary"
        }
        ModuleLoader {
            id: secondary; width: 1; height: 1; visible: false; screenName: "secondary"
        }
        Timer {
            interval: 80; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var musicItem: null
            property var radioItem: null
            function find(object, name) {
                if (!object) return null;
                if (object.objectName === name) return object;
                for (const child of object.children || []) {
                    const match = find(child, name);
                    if (match) return match;
                }
                return null;
            }
            function content(id, loader) {
                const holder = find((loader || overlay).item, "retained-" + id);
                if (!holder) return null;
                for (const child of holder.children || []) if (child.item) return child.item;
                return null;
            }
            function fail(message) { console.error("RETAINED FAIL", message); Qt.quit(); }
            onTriggered: {
                if (++ticks > 100) { fail("Timed out at step " + step); return; }
                if (step === 0) {
                    if (!Plugins.find("music") || !Plugins.find("radio") || !Plugins.find("games")) return;
                    ShellState.monitor = "primary";
                    ShellState.openPlugin("music"); step++; ticks = 0;
                } else if (step === 1) {
                    musicItem = content("music");
                    if (!musicItem) return;
                    ShellState.requestKeepRunning("music", true);
                    ShellState.toggle("left");
                    if (ShellState.pluginId !== "music" || ShellState.panel !== "left") { fail("Drawer displaced Music"); return; }
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 2) {
                    if (!overlay.item || content("music") !== musicItem) { fail("Desktop stopped Music"); return; }
                    ShellState.monitor = "secondary";
                    ShellState.openPlugin("radio"); step++; ticks = 0;
                } else if (step === 3) {
                    radioItem = content("radio", secondary);
                    if (!radioItem) return;
                    ShellState.requestKeepRunning("radio", true);
                    if (content("music") !== musicItem) { fail("Opening Radio stopped Music"); return; }
                    ShellState.toggle("left", "primary");
                    ShellState.dismissPanel();
                    if (ShellState.monitor !== "secondary" || content("radio", secondary) !== radioItem) { fail("Drawer moved Radio"); return; }
                    Plugins.reload(); step++; ticks = 0;
                } else if (step === 4) {
                    if (Plugins.scan.running) return;
                    if (content("music") !== musicItem || content("radio", secondary) !== radioItem) { fail("Reload stopped a player"); return; }
                    ShellState.openPlugin("games"); step++; ticks = 0;
                } else if (step === 5) {
                    const game = find(secondary.item, "moduleContent");
                    if (!game || !game.item) return;
                    const gameItem = game.item;
                    ShellState.toggle("left", "primary");
                    if (game.item !== gameItem || ShellState.pluginMonitor !== "secondary") { fail("Drawer closed Games on another monitor"); return; }
                    ShellState.dismissPanel();
                    if (ShellState.monitor !== "secondary") { fail("Drawer returned Games to wrong monitor"); return; }
                    if (content("music") !== musicItem || content("radio", secondary) !== radioItem) { fail("Games stopped a player"); return; }
                    musicItem.host.requestKeepRunning("radio", false);
                    if (!ShellState.retentionRequests.radio) { fail("Music host changed Radio retention"); return; }
                    musicItem.host.close();
                    if (ShellState.pluginId !== "games") { fail("Hidden Music host closed Games"); return; }
                    step++; ticks = 0;
                } else if (step === 6) {
                    if (content("music")) { fail("Closing Music did not release it"); return; }
                    content("games", secondary).host.close();
                    if (!secondary.item || content("radio", secondary) !== radioItem) { fail("Closing Games stopped Radio"); return; }
                    ShellState.stopPlugin("radio"); step++; ticks = 0;
                } else if (step === 7) {
                    if (overlay.item || secondary.item) return;
                    ShellState.monitor = "primary";
                    ShellState.openPlugin("music"); step++; ticks = 0;
                } else if (step === 8) {
                    if (!content("music")) return;
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 9) {
                    if (overlay.item) return;
                    ShellState.openPlugin("games"); step++; ticks = 0;
                } else if (step === 10) {
                    const game = content("games");
                    if (!game) return;
                    game.host.requestKeepRunning("games", true);
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 11) {
                    if (!content("games")) { fail("A general module could not request retention"); return; }
                    content("games").host.requestKeepRunning("games", false); step++; ticks = 0;
                } else if (step === 12) {
                    if (overlay.item) return;
                    console.log("RETAINED PASS: drawer, Desktop, idle release, general retention, multi-monitor switching, reload, and explicit stop");
                    Qt.quit();
                }
            }
        }
    }
}
