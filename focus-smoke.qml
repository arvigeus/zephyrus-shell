//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "core"
import "shell"

ShellRoot {
    id: root
    readonly property var testScreen: Quickshell.screens.find(s => s.name === "ZEPHYRUS-FOCUS") || null
    property ModuleLoader modules: ModuleLoader { screenName: "*"; readyToLoad: false; anchors.fill: parent }
    Loader {
        active: !!root.testScreen
        sourceComponent: ShellScreen { screen: root.testScreen; sharedModules: root.modules }
    }
    FloatingWindow {
        id: target
        screen: root.testScreen
        title: "Zephyrus keyboard focus test"
        implicitWidth: 640; implicitHeight: 480
        color: "#202020"
        TextInput { id: field; anchors.fill: parent; focus: true; color: "white" }
    }
    Process { id: input; command: [Quickshell.env("ZEPHYRUS_FOCUS_INPUT"), "30"]; onExited: code => { if (code) check.fail("Input client exited with " + code); } }
    Timer {
        id: check
        interval: 120; running: true; repeat: true
        property int step: 0
        property int ticks: 0
        property int cycle: 0
        property var instance: null
        property real moduleHeight: 0
        function find(item, name) {
            if (!item) return null;
            if (item.objectName === name) return item;
            for (const child of item.children || []) {
                const found = find(child, name);
                if (found) return found;
            }
            return null;
        }
        function fail(message) { console.error("FOCUS FAIL:", message); stop(); Qt.quit(); }
        function advance(value) { step = value; ticks = 0; }
        function send(key) { input.command = [Quickshell.env("ZEPHYRUS_FOCUS_INPUT"), String(key)]; input.running = true; }
        onTriggered: {
            if (++ticks > 45) { fail("Timeout at step " + step + ", panel=" + ShellState.panel + ", active=" + target.contentItem.Window.active); return; }
            if (step === 0) {
                if (!root.testScreen || !target.contentItem.Window.active) return;
                const window = WindowList.windows.find(w => w.title === target.title);
                if (!window) return;
                WindowList.moveToMonitor(window, root.testScreen.name);
                advance(10);
            } else if (step === 10) {
                const window = WindowList.windows.find(w => w.title === target.title);
                const client = window ? WindowList.clientFor(window) : null;
                const monitor = WindowList.monitors.find(m => m.name === root.testScreen.name);
                if (!client || !monitor || client.lastIpcObject.monitor !== monitor.id || !target.contentItem.Window.active) return;
                field.forceActiveFocus(); send(30); advance(1);
            } else if (step === 1 && !input.running) {
                if (field.text !== "a") { fail("Initial keyboard delivery failed"); return; }
                ShellState.monitor = root.testScreen.name;
                ShellState.openPlugin("apps"); advance(2);
            } else if (step === 2) {
                if (!modules.item || !modules.item.currentModule) return;
                if (cycle && modules.item.currentModule !== instance) { fail("Return replaced the module"); return; }
                instance = modules.item.currentModule;
                if (!cycle) moduleHeight = instance.height;
                if (target.contentItem.Window.active) return;
                if (find(instance, "appsSearchField").text !== "b".repeat(cycle)) { fail("Return lost the query"); return; }
                send(48); advance(12);
            } else if (step === 12 && !input.running) {
                if (find(instance, "appsSearchField").text !== "b".repeat(cycle + 1)) { fail("Module did not receive the key"); return; }
                send(1); advance(3);
            } else if (step === 3 && !input.running && !ShellState.pluginId) {
                if (!target.contentItem.Window.active) { fail("Escape stranded native keyboard focus"); return; }
                send(30); advance(4);
            } else if (step === 4 && !input.running) {
                if (field.text !== "a".repeat(cycle + 2)) { fail("No key delivery after Escape"); return; }
                if (++cycle < 3) { ShellState.openPlugin("apps"); advance(2); }
                else { ShellState.toggle("center", root.testScreen.name); advance(17); }
            } else if (step === 17 && ticks > 3) {
                if (instance.height !== moduleHeight) { fail("Desktop popup resized hidden module: " + instance.height + " vs " + moduleHeight); return; }
                send(1); advance(18);
            } else if (step === 18 && !input.running && !ShellState.panel && target.contentItem.Window.active) {
                ShellState.openPlugin("apps"); advance(5);
            } else if (step === 5 && ShellState.panel === "module" && ticks > 3) {
                ShellState.toggle("left", root.testScreen.name); advance(6);
            } else if (step === 6 && ticks > 3) {
                send(1); advance(7);
            } else if (step === 7 && !input.running && ShellState.panel === "module") {
                if (modules.item.currentModule !== instance) { fail("Drawer replaced the module"); return; }
                ShellState.toggle("center", root.testScreen.name); advance(8);
            } else if (step === 8 && ticks > 3) {
                send(1); advance(9);
            } else if (step === 9 && !input.running && ShellState.panel === "module") {
                ShellState.stopPlugin("apps"); advance(11);
            } else if (step === 11 && !modules.item && target.contentItem.Window.active) {
                send(30); advance(13);
            } else if (step === 13 && !input.running) {
                if (field.text !== "aaaaa") { fail("Sidebar close stranded the keyboard"); return; }
                ShellState.toggle("center", root.testScreen.name); advance(14);
            } else if (step === 14 && ticks > 3) {
                send(1); advance(15);
            } else if (step === 15 && !input.running && !ShellState.panel && target.contentItem.Window.active) {
                send(30); advance(16);
            } else if (step === 16 && !input.running) {
                if (field.text !== "aaaaaa") { fail("Desktop popup stranded the keyboard"); return; }
                console.log("FOCUS PASS: module typing, three Escape/return cycles, preserved query, drawer and popup Escape, explicit stop, desktop popup and native key delivery");
                stop(); Qt.quit();
            }
        }
    }
}
