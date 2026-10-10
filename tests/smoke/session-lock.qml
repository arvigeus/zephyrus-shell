import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../settings"

Scope {
    id: root
    property int step: 0
    property int ticks: 0
    property bool executions: false
    property var toggle: null
    Component.onCompleted: ThemeRuntime.refresh()
    FileView { id: profile; path: Quickshell.env("ZEPHYRUS_IDLE_PROFILE"); blockLoading: true; printErrors: false }
    FloatingWindow {
        id: window
        implicitWidth: 490; implicitHeight: 360
        color: Theme.background
        SessionActions {
            id: actions
            x: 16; y: 270; width: 458
            machine: QtObject {
                property bool busy: false
                property var snapshot: ({hyprland: true})
                function run(name, value) { root.executions = true; }
            }
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        // Popup content belongs to the control's QObject data before opening
        // and moves onto the overlay when shown.
        const descendants = Array.from(item.children || []).concat(Array.from(item.data || []));
        if (item.contentItem) descendants.push(item.contentItem);
        for (const child of descendants) { const match = find(child, name); if (match) return match; }
        return null;
    }
    function fail(message) { console.error("SESSION LOCK FAIL:", message); Qt.quit(); }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (++root.ticks > 120) { root.fail("Timeout at step " + root.step + " " + SessionLock.error); return; }
            if (!SessionLock.loaded || SessionLock.busy) return;
            if (SessionLock.error || root.executions) { root.fail(SessionLock.error || "Executed a power action"); return; }
            const sleep = root.find(actions, "session-action-suspend");
            if (!sleep) { root.fail("Missing Sleep control"); return; }
            if (root.step === 0) {
                if (!root.toggle) {
                    root.find(actions, "session-sleep-options").clicked();
                    root.toggle = root.find(window.contentItem, "session-lock-toggle");
                    return;
                }
                if (SessionLock.paused || !root.toggle.enabled || root.toggle.iconName !== "lock-open") { root.fail("Initial state"); return; }
                root.toggle.clicked(); root.step = 1;
            } else if (root.step === 1 && SessionLock.paused) {
                profile.reload();
                if (profile.text().includes("before_sleep_cmd") || profile.text().includes("timeout = 1800")) { root.fail("Paused profile still locks/sleeps"); return; }
                if (!profile.text().includes("timeout = 360") || sleep.iconName !== "lock-open" || root.toggle.text !== "Restore locking") { root.fail("Paused controls/profile"); return; }
                // Reopening Settings and lid cleanup of awake modes must not
                // erase the independent session lock preference.
                actions.visible = false; KeepAwake.setMode("off"); actions.visible = true;
                SessionLock.refresh(); root.step = 2;
            } else if (root.step === 2) {
                if (!SessionLock.paused) { root.fail("Pause lost when reopening Settings"); return; }
                root.find(actions, "session-sleep-options").clicked();
                root.toggle.parent.grabToImage(result => {
                    result.saveToFile(Paths.file("tests/artifacts/session-lock.png"));
                    root.toggle.clicked(); root.step = 3;
                });
                root.step = -1;
            } else if (root.step === 3 && !SessionLock.paused) {
                profile.reload();
                if (!profile.text().includes("inhibit_sleep = 3") || !profile.text().includes("timeout = 1800") || sleep.iconName !== "moon") return;
                console.log("SESSION LOCK PASS: real Settings action, session state, idle profiles, reopen, lock-open indicator and restoration");
                Qt.quit();
            }
        }
    }
}
