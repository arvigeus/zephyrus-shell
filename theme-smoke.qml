//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "widgets" as W
import "settings"

ShellRoot {
    id: root
    property int step: 0
    property int attempts: 0
    property string config: Quickshell.env("XDG_CONFIG_HOME")
    property var original: ({})
    Component.onCompleted: ThemeRuntime.start()
    FileView { id: input; path: root.config + "/zephyrus-shell/theme.json"; printErrors: false; blockLoading: true; atomicWrites: true }
    FileView { id: kde; path: root.config + "/kdeglobals"; printErrors: false; blockLoading: true }
    FloatingWindow {
        implicitWidth: 320; implicitHeight: 160; color: Theme.surface
        W.Label { id: label; anchors.centerIn: parent; text: "Shared appearance" }
        W.Icon { id: glyph; name: "wifi"; width: 24; height: 24; x: 12; y: 12 }
    }
    HardwareSection {
        id: systemCard
        width: 490
        machine: QtObject { property var snapshot: ({}); property bool busy: false }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function edit(value) { input.setText(JSON.stringify(value)); }
    function fail(message) { console.error("THEME FAIL:", message); Qt.quit(); }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (++root.attempts > 150) { root.fail("Timed out at step " + root.step + ": " + Theme.error); return; }
            if (root.step === 0 && Theme.loaded) {
                if (Theme.error || Theme.mode !== "dark") { root.fail("Initial theme"); return; }
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
                input.reload();
                if (JSON.parse(input.text()).mode !== "light") return;
                root.find(systemCard, "system-theme-toggle").clicked(); root.step = 5;
            } else if (root.step === 5 && !ThemeRuntime.busy && Theme.mode === "dark") {
                console.log("THEME PASS: real adapters, atomic watching, fonts, invalid edit recovery and persisted Settings button roundtrip");
                Qt.quit();
            }
        }
    }
}
