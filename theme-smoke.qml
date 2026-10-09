//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "widgets" as W
import "settings"
import "shell"

ShellRoot {
    id: root
    property int step: 0
    property int attempts: 0
    property string waitReason: ""
    property string config: Quickshell.env("XDG_CONFIG_HOME")
    property var original: ({})
    property var projectInstance: null
    readonly property bool coldLight: Quickshell.env("ZEPHYRUS_THEME_COLD_LIGHT") === "1"
    Component.onCompleted: ThemeRuntime.start()
    FileView { id: input; path: root.config + "/zephyrus-shell/theme.json"; printErrors: false; blockLoading: true; atomicWrites: true }
    FileView { id: kde; path: root.config + "/kdeglobals"; printErrors: false; blockLoading: true }
    FloatingWindow {
        implicitWidth: 1100; implicitHeight: 700; color: Theme.surface
        ModuleLoader { id: overlay; anchors.fill: parent }
        W.Label { id: label; anchors.centerIn: parent; text: "Shared appearance" }
        W.Icon { id: glyph; name: "wifi"; width: 24; height: 24; x: 12; y: 12 }
    }
    HardwareSection {
        id: systemCard
        width: 490
        machine: QtObject { property var snapshot: ({}); property bool busy: false }
    }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function projectColors() {
        const holder = root.find(overlay.item, "retained-projects");
        const loader = holder ? holder.children.find(child => child.item) : null;
        if (!loader || !loader.item) { waitReason = "No Projects loader"; return false; }
        if (projectInstance && loader.item !== projectInstance) { root.fail("Retained module was recreated"); return false; }
        const field = root.find(loader.item, "projectsSearchField");
        const count = root.find(loader.item, "projectsResultCount");
        if (!field || !count) { waitReason = "Missing Projects search/count controls"; return false; }
        if (field.color.toString() !== Theme.text.toString()) { root.fail("Module widget text: " + field.color + " expected " + Theme.text); return false; }
        if (count.color.toString() !== Theme.muted.toString()) { root.fail("Module core text: " + count.color + " expected " + Theme.muted); return false; }
        return true;
    }
    function edit(value) { input.setText(JSON.stringify(value)); }
    function fail(message) { console.error("THEME FAIL:", message); Qt.quit(); }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (++root.attempts > 150) { root.fail("Timed out at step " + root.step + ": " + Theme.error + " mode=" + Theme.mode + " font=" + Theme.fontSize + " " + root.waitReason + " busy=" + ThemeRuntime.busy + " source=" + input.text().slice(0, 100)); return; }
            if (root.step === 0 && Theme.loaded && !ThemeRuntime.busy) {
                if (!Modules.find("projects")) return;
                if (!ShellState.pluginId) { ShellState.openPlugin("projects"); return; }
                if (!root.projectColors()) return;
                if (Theme.error || Theme.mode !== (root.coldLight ? "light" : "dark")) { root.fail("Initial theme"); return; }
                if (root.coldLight) {
                    console.log("THEME PASS: fresh light session and late-loaded module share colors without Terminal");
                    Qt.quit(); return;
                }
                kde.reload();
                // Edit the real source that the production runtime watches.
                input.reload();
                const settings = JSON.parse(input.text());
                root.original = settings;
                const changed = JSON.parse(JSON.stringify(settings));
                changed.mode = "light"; changed.font = "DejaVu Sans"; changed.font_size = 13;
                changed.palettes.light.accent = "#345678";
                root.edit(changed); root.step = 1;
            } else if (root.step === 1 && Theme.mode === "light" && Theme.fontSize === 13) {
                if (!root.projectColors()) return;
                kde.reload();
                if (!kde.text().includes("font=DejaVu Sans,13,") || !kde.text().includes("DecorationFocus=52,86,120")) return;
                if (label.font.family !== "DejaVu Sans" || label.font.pixelSize !== Theme.sp(14)) { root.fail("Text did not follow fonts"); return; }
                if (glyph.status !== Image.Ready) return;
                if (!decodeURIComponent(glyph.source.toString()).includes('stroke="' + Theme.text.toString() + '"')) { root.fail("Icon did not follow foreground"); return; }
                input.setText("{ invalid"); root.step = 2;
            } else if (root.step === 2 && Theme.error) {
                if (Theme.mode !== "light") { root.fail("Invalid file replaced the last good theme"); return; }
                root.edit(root.original); root.step = 3;
            } else if (root.step === 3 && !Theme.error && Theme.mode === "dark" && Theme.fontSize === 11) {
                if (ThemeRuntime.busy) return;
                const toggle = root.find(systemCard, "system-theme-toggle");
                if (!toggle || !toggle.enabled) { root.fail("System theme button unavailable"); return; }
                toggle.clicked(); root.step = 4;
            } else if (root.step === 4 && !ThemeRuntime.busy && Theme.mode === "light") {
                if (!root.projectColors()) return;
                input.reload();
                if (JSON.parse(input.text()).mode !== "light") return;
                const holder = root.find(overlay.item, "retained-projects");
                root.projectInstance = holder.children.find(child => child.item).item;
                // Retain a real module, hide it through Desktop, and change mode.
                ShellState.showDesktop();
                root.find(systemCard, "system-theme-toggle").clicked(); root.step = 5;
            } else if (root.step === 5 && !ThemeRuntime.busy && Theme.mode === "dark") {
                if (!root.projectColors()) return;
                ShellState.openPlugin("files"); root.step = 6;
            } else if (root.step === 6 && !ThemeRuntime.busy) {
                const loader = root.find(overlay.item, "moduleContent");
                if (!loader || !loader.item) return;
                root.find(systemCard, "system-theme-toggle").clicked(); root.step = 7;
            } else if (root.step === 7 && !ThemeRuntime.busy && Theme.mode === "light") {
                if (!root.projectColors()) return;
                ShellState.openPlugin("projects"); root.step = 8;
            } else if (root.step === 8) {
                if (!root.projectColors()) return;
                root.projectInstance.host.close();
                ShellState.stopPlugin("files");
                root.projectInstance = null;
                root.step = 9;
            } else if (root.step === 9 && !overlay.item) {
                ShellState.openPlugin("projects"); root.step = 10;
            } else if (root.step === 10) {
                if (!root.projectColors()) return;
                console.log("THEME PASS: real adapters, atomic watching, fonts, invalid edits, Settings roundtrip, retained and recreated module colors");
                Qt.quit();
            }
        }
    }
}
