import QtQuick
import Quickshell
import "../../core"
import "../../shell"

Scope {
    FloatingWindow {
        implicitWidth: 1280; implicitHeight: 800
        color: Theme.background
        ModuleLoader {
            id: overlay
            parent: ShellState.moduleMonitor === "secondary" ? secondarySurface.item : primarySurface
            anchors.fill: parent
        }
        Item { id: primarySurface; anchors.fill: parent }
        Loader { id: secondarySurface; anchors.fill: parent; sourceComponent: Item {} }
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
                    if (!Modules.find("music") || !Modules.find("radio") || !Modules.find("games")) return;
                    ShellState.monitor = "primary";
                    ShellState.openModule("music"); step++; ticks = 0;
                } else if (step === 1) {
                    musicItem = content("music");
                    if (!musicItem) return;
                    ShellState.toggle("left");
                    if (ShellState.moduleId !== "music" || ShellState.panel !== "left") { fail("Drawer displaced Music"); return; }
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 2) {
                    if (!overlay.item || content("music") !== musicItem) { fail("Desktop stopped Music"); return; }
                    ShellState.monitor = "secondary";
                    ShellState.openModule("radio"); step++; ticks = 0;
                } else if (step === 3) {
                    radioItem = content("radio", overlay);
                    if (!radioItem) return;
                    if (content("music") !== musicItem) { fail("Opening Radio stopped Music"); return; }
                    ShellState.toggle("left", "primary");
                    ShellState.dismissPanel();
                    if (ShellState.monitor !== "secondary" || content("radio", overlay) !== radioItem) { fail("Drawer moved Radio"); return; }
                    step++; ticks = 0;
                } else if (step === 4) {
                    if (content("music") !== musicItem || content("radio", overlay) !== radioItem) { fail("Panel dismissal stopped a player"); return; }
                    ShellState.openModule("games"); step++; ticks = 0;
                } else if (step === 5) {
                    const game = find(overlay.item, "moduleContent");
                    if (!game || !game.item) return;
                    const gameItem = game.item;
                    ShellState.toggle("left", "primary");
                    if (game.item !== gameItem || ShellState.moduleMonitor !== "secondary") { fail("Drawer closed Games on another monitor"); return; }
                    ShellState.dismissPanel();
                    if (ShellState.monitor !== "secondary") { fail("Drawer returned Games to wrong monitor"); return; }
                    if (content("music") !== musicItem || content("radio", overlay) !== radioItem) { fail("Games stopped a player"); return; }
                    musicItem.host.close();
                    if (ShellState.moduleId !== "games") { fail("Hidden Music host closed Games"); return; }
                    step++; ticks = 0;
                } else if (step === 6) {
                    if (content("music")) { fail("Closing Music did not release it"); return; }
                    content("games", overlay).host.close();
                    if (!overlay.item || content("radio", overlay) !== radioItem) { fail("Closing Games stopped Radio"); return; }
                    ShellState.stopModule("radio"); step++; ticks = 0;
                } else if (step === 7) {
                    if (overlay.item) return;
                    ShellState.monitor = "primary";
                    ShellState.openModule("music"); step++; ticks = 0;
                } else if (step === 8) {
                    musicItem = content("music");
                    if (!musicItem) return;
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 9) {
                    if (content("music") !== musicItem) { fail("Desktop destroyed idle Music"); return; }
                    musicItem.host.close();
                    ShellState.openModule("games"); step++; ticks = 0;
                } else if (step === 10) {
                    const game = content("games");
                    if (!game) return;
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 11) {
                    if (!content("games")) { fail("Desktop destroyed idle Games"); return; }
                    content("games").host.close(); step++; ticks = 0;
                } else if (step === 12) {
                    if (overlay.item) return;
                    ShellState.monitor = "secondary";
                    ShellState.openModule("music"); step++; ticks = 0;
                } else if (step === 13) {
                    musicItem = content("music");
                    if (!musicItem) return;
                    ShellState.reconcileScreens(["primary"]);
                    secondarySurface.active = false;
                    step++; ticks = 0;
                } else if (step === 14) {
                    if (content("music") !== musicItem || ShellState.moduleMonitor !== "primary") { fail("Unplugging a screen replaced retained resources"); return; }
                    ShellState.showDesktop(); step++; ticks = 0;
                } else if (step === 15) {
                    if (content("music") !== musicItem) { fail("Desktop stopped migrated Music"); return; }
                    musicItem.host.close(); step++; ticks = 0;
                } else if (step === 16) {
                    if (overlay.item) return;
                    console.log("RETAINED PASS: drawer, Desktop, idle module retention, multi-monitor switching and explicit stop");
                    Qt.quit();
                }
            }
        }
    }
}
