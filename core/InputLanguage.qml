pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root
    property string language: "en"
    property string secondary: "bg"
    property bool available: false
    property string error: ""
    property string keyboard: ""
    property bool refreshPending: false
    property string selectionPending: ""
    property string selectionCode: ""
    property bool requestActive: false
    signal selectionFinished(string code, bool success)
    readonly property bool busy: requestActive || refreshPending || selectionPending !== ""
    readonly property bool selecting: (requestActive && command.action === "select") || selectionPending !== ""
    readonly property string displayLanguage: selecting ? selectionCode : language
    readonly property string flag: ({bg: "🇧🇬", vi: "🇻🇳"})[displayLanguage] || ""
    readonly property string description: error || (selecting ? "Switching to " + languageName(displayLanguage)
        : languageName(language) + " · Alt+Shift: English / " + languageName(secondary))
    function languageName(code) { return ({en: "English", bg: "Български (фонетична)", vi: "Tiếng Việt (Telex)"})[code] || code; }
    function request(action, code) {
        if (requestActive) {
            if (action === "select") selectionPending = code;
            else refreshPending = true;
            return;
        }
        if (action === "select") keyboard = ""; // Menu selections change all keyboards.
        command.action = action;
        command.code = code || "";
        command.failure = "";
        command.command = ["python3", Paths.file("scripts/input-language.py"), action, action === "select" ? code : keyboard];
        requestActive = true;
        command.running = true;
    }
    function next() {
        if (requestActive) return;
        if (selectionPending) {
            const code = selectionPending;
            selectionPending = "";
            request("select", code);
        } else if (refreshPending) {
            refreshPending = false;
            refresh();
        }
    }
    function refresh() { request("status"); }
    function select(code) {
        if (["en", "bg", "vi"].includes(code)) {
            selectionCode = code;
            request("select", code);
        }
    }
    function handleLayoutEvent(name, data) {
        if (name === "activelayout") {
            // Copy the keyboard name now: Quickshell reuses its event object.
            keyboard = data.slice(0, data.indexOf(","));
            layoutChanged.restart();
        } else if (name === "configreloaded") layoutChanged.restart();
    }
    property Process command: Process {
        property string action: "status"
        property string code: ""
        // Each request's outcome replaces the previous error, so a recovered
        // provider or compositor does not leave a stale error in the tooltip.
        property string failure: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                try {
                    const state = JSON.parse(text);
                    if (state.keyboards) {
                        root.available = false;
                        root.secondary = "bg";
                        const device = state.keyboards.find(k => k.name === root.keyboard)
                            || state.keyboards.find(k => k.main) || state.keyboards[0];
                        if (device) {
                            root.language = device.active_layout_index !== undefined
                                ? ((device.layout || "us").split(",")[device.active_layout_index] === "bg" ? "bg" : "en")
                                : ((device.active_keymap || "").toLowerCase().includes("bulgarian") ? "bg" : "en");
                        }
                    } else {
                        root.available = state.available === true;
                        if (state.language) root.language = state.language;
                        if (state.secondary) root.secondary = state.secondary;
                    }
                    if (state.error) root.command.failure = state.error;
                } catch (error) { root.command.failure = "Could not read input language."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.command.failure = text.trim(); }
        onExited: (exitCode, exitStatus) => {
            root.error = root.command.failure || (exitCode ? "Could not change or read input language." : "");
            if (action === "select") {
                if (exitCode) root.refreshPending = true;
                root.selectionFinished(code, exitCode === 0);
            }
            // Process.running can become false before exit callbacks and
            // collected output finish. Keep the request busy through those.
            root.requestActive = false;
            Qt.callLater(root.next);
        }
    }
    property Timer updates: Timer {
        // Input providers can change mode without a compositor layout event.
        // Only poll while the user has explicitly selected Vietnamese.
        interval: 1000; repeat: true
        running: root.available && root.secondary === "vi"
        onTriggered: root.refresh()
    }
    property Timer layoutChanged: Timer { interval: 80; onTriggered: root.refresh() }
    property Connections events: Connections {
        target: Hyprland
        function onRawEvent(event) { root.handleLayoutEvent(event.name, event.data); }
    }
    Component.onCompleted: if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) refresh();
}
