//@ pragma UseQApplication
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "core"
import "shell"

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    property int captureTicks: 0
    property var first: null
    property var second: null
    property string sessionPids: ""
    property string testPath: Quickshell.env("ZEPHYRUS_TERMINAL_TEST")
    Component.onCompleted: ThemeRuntime.refresh()
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function fail(message) { console.error("TERMINAL FAIL", step, message); Qt.quit(); }
    FileView { id: configuration; path: root.testPath + "/config/zephyrus-shell/terminal.json"; blockLoading: true; atomicWrites: true }
    FileView { id: themeSource; path: root.testPath + "/config/zephyrus-shell/theme.json"; printErrors: false; atomicWrites: true }
    FileView { id: resultFile; path: root.testPath + "/result"; printErrors: false; blockLoading: true }
    FileView { id: pids; path: root.testPath + "/pids"; printErrors: false; atomicWrites: true }
    FloatingWindow {
        implicitWidth: 1100; implicitHeight: 650; color: Theme.background
        TestCase { id: keyboard; when: false }
        ModuleLoader { id: overlay; screenName: "*"; anchors.fill: parent }
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (++root.ticks > 200) { root.fail("Timeout"); return; }
            const m = overlay.item ? overlay.item.currentModule : null;
            if (root.step === 0) {
                if (!Modules.find("terminal") || !Theme.loaded) return;
                ShellState.openPlugin("terminal"); root.step = 1;
            } else if (root.step === 1) {
                if (!m || !m.currentTerminal || m.commandsLoading || root.ticks < 12) return;
                root.first = m.currentTerminal;
                if (m.tabCount !== 1) { root.fail("Initial tab"); return; }
                root.find(m, "terminalCommands").clicked(); root.step = 2;
            } else if (root.step === 2) {
                if (m.commandsLoading) return;
                if (m.commands.length !== 1 || m.commands[0].name !== "Fixture") { root.fail("Commands config"); return; }
                root.step = 99;
                m.commandsMenu.contentItem.grabToImage(result => {
                    result.saveToFile("tests/artifacts/terminal-commands.png");
                    root.find(m.commandsMenu.contentItem, "terminalSavedCommand").clicked(); root.step = 3;
                });
            } else if (root.step === 3) {
                resultFile.reload();
                if (resultFile.text() !== "first:/tmp") return;
                root.find(m, "terminalNewTab").clicked(); root.step = 4;
            } else if (root.step === 4) {
                if (!m.currentTerminal || m.currentTerminal === root.first) return;
                root.second = m.currentTerminal;
                if (m.tabCount !== 2) { root.fail("New tab"); return; }
                const command = "printf '%s' \"${ZE_TEST-unset}:$PWD\" > '" + root.testPath + "/result'";
                m.runCommand(command);
                if (m.message) return;
                root.step = 5;
            } else if (root.step === 5) {
                resultFile.reload();
                if (resultFile.text() !== "unset:" + Quickshell.env("HOME")) return;
                m.selectTab(0);
                if (m.currentTerminal !== root.first) { root.fail("Switch replaced first PTY"); return; }
                m.runCommand("printf '%s' \"$ZE_TEST:$PWD\" > '" + root.testPath + "/result'");
                root.step = 6;
            } else if (root.step === 6) {
                resultFile.reload();
                if (resultFile.text() !== "first:/tmp") return;
                configuration.setText(JSON.stringify({commands:[{name:"Reloaded",command:"pwd"}]}));
                root.find(m, "terminalCommands").clicked(); root.step = 7;
            } else if (root.step === 7) {
                if (m.commandsLoading || m.commands[0].name !== "Reloaded") return;
                m.closeCommands();
                configuration.setText("{invalid");
                root.find(m, "terminalCommands").clicked(); root.step = 8;
            } else if (root.step === 8) {
                if (m.commandsLoading) return;
                if (!m.commandsError || m.commands.length) { root.fail("Invalid config kept commands"); return; }
                m.closeCommands();
                themeSource.setText('{"mode":"light"}');
                ThemeRuntime.refresh();
                root.step = 9;
            } else if (root.step === 9) {
                if (Theme.mode !== "light") return;
                if (root.find(root.first, "terminalSurface").fillColor.toString() !== Theme.background.toString()) return;
                if (++root.captureTicks < 4) return;
                root.captureTicks = 0;
                if (m.currentTerminal !== root.first || !root.first.scrollback()) { root.fail("Theme change replaced session"); return; }
                root.step = 99;
                overlay.grabToImage(result => { result.saveToFile("tests/artifacts/terminal-light.png"); root.step = 10; });
            } else if (root.step === 10) {
                themeSource.setText('{"mode":"dark"}');
                ThemeRuntime.refresh();
                root.step = 19;
            } else if (root.step === 19) {
                if (Theme.mode !== "dark" || root.find(root.first, "terminalSurface").fillColor.toString() !== Theme.background.toString()) return;
                if (++root.captureTicks < 4) return;
                root.step = 99;
                overlay.grabToImage(result => { result.saveToFile("tests/artifacts/terminal-dark.png"); root.step = 16; });
            } else if (root.step === 16) {
                root.first.forceTerminalFocus();
                keyboard.keyClick(Qt.Key_E);
                if (!root.first.runCommand("pwd")) { root.fail("Draft input was overwritten"); return; }
                keyboard.keyClick(Qt.Key_U, Qt.ControlModifier);
                m.runCommand("sleep 1"); root.step = 11;
            } else if (root.step === 11) {
                if (!root.first.runCommand("pwd")) { root.fail("Busy foreground program received command"); return; }
                root.sessionPids = root.first.processId() + "\n" + root.second.processId() + "\n";
                pids.setText(root.sessionPids);
                ShellState.showDesktop(); root.step = 12;
            } else if (root.step === 12) {
                if (!overlay.item || !ShellState.runningPluginIds.includes("terminal")) { root.fail("Desktop destroyed retained terminal"); return; }
                ShellState.openPlugin("terminal"); root.step = 13;
            } else if (root.step === 13) {
                if (!m) return;
                if (m.currentTerminal !== root.first || m.tabCount !== 2) { root.fail("Return lost tabs"); return; }
                m.selectTab(1);
                m.restartShell(); root.step = 17;
            } else if (root.step === 17) {
                if (!m.currentTerminal || m.currentTerminal === root.second) return;
                if (m.tabCount !== 2) { root.fail("Restart lost tab"); return; }
                root.sessionPids += m.currentTerminal.processId() + "\n";
                pids.setText(root.sessionPids);
                m.closeTab(1);
                if (m.currentTerminal !== root.first || m.tabCount !== 1) { root.fail("Close wrong session"); return; }
                m.addTab(); root.step = 18;
            } else if (root.step === 18) {
                if (!m.currentTerminal || m.currentTerminal === root.first) return;
                m.runCommand("exit");
                if (m.message) return;
                root.sessionPids += m.currentTerminal.processId() + "\n";
                pids.setText(root.sessionPids);
                root.step = 20;
            } else if (root.step === 20) {
                if (m.tabCount !== 1) return;
                if (m.currentTerminal !== root.first) { root.fail("Shell exit closed another tab"); return; }
                root.step = 14;
            } else if (root.step === 14) {
                ShellState.stopPlugin("terminal"); root.step = 15;
            } else if (root.step === 15 && !overlay.item) {
                console.log("TERMINAL PASS: commands, isolated PTYs, menu reload/error, live colors, draft/busy guards, retention, restart, shell exit and close");
                Qt.quit();
            }
        }
    }
}
