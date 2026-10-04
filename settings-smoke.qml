import QtQuick
import Quickshell
import "core"
import "drawers"
import "shell"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 850; implicitHeight: 1100
        color: Theme.background
        QtObject {
            id: safeMachine
            property var snapshot: ({hyprland: true})
            property bool busy: false
            function run(name, value) {
                test.executions++; test.lastAction = name; test.lastValue = value === undefined ? "" : String(value);
                if (name === "cpu-boost") snapshot = {hardware:{boost:value === "on" ? "1" : "0", boostControlError:""}};
            }
        }
        Item {
            id: canvas
            anchors.fill: parent
        ClockPill { x: 20; y: 20 }
        DrawerSlide {
            id: drawer
            x: 360; width: 490; height: parent.height
            side: "right"; retainContent: true; opened: true
            contentSource: Qt.resolvedUrl("drawers/ControlDrawer.qml")
        }
        }
        Timer {
            id: test
            interval: 80; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var saved: null
            property var button: null
            property int activations: 0
            property int executions: 0
            property string lastAction: ""
            property string lastValue: ""
            property double checked: 0
            function fail(message) { console.error("SETTINGS FAIL", message); stop(); Qt.quit(); }
            function find(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) { const result = find(child, name); if (result) return result; }
                return null;
            }
            onTriggered: {
                if (++ticks > 130) { fail("Timeout at step " + step); return; }
                if (!drawer.item || HardwareSnapshot.busy || !Profiles.loaded || Profiles.busy) return;
                if (step === 0) {
                    // Startup profile application legitimately invalidates the
                    // snapshot. Wait for it before measuring drawer reuse.
                    if (Profiles.startup || Profiles.applying || Profiles.settle.running) return;
                    if (!HardwareSnapshot.checkedAt || HardwareSnapshot.events.running || HardwareSnapshot.refreshPending) return;
                    saved = drawer.item;
                    checked = HardwareSnapshot.checkedAt;
                    button = find(saved, "session-action-poweroff");
                    if (!button || button.holdDuration !== 2000) { fail("Power action does not require a 2s hold"); return; }
                    find(saved, "session-actions").machine = safeMachine;
                    button.activated.connect(() => test.activations++);
                    // Capture/cancel the real timer without executing a system action.
                    button.holdDuration = 1000;
                    button.down = true;
                    drawer.opened = false;
                    step++;
                } else if (step === 1 && !drawer.showing) {
                    if (drawer.item !== saved) { fail("Closing destroyed cached Settings"); return; }
                    drawer.opened = true; step++;
                } else if (step === 2 && ticks > 18) {
                    if (activations) { fail("Hidden power button completed a hold"); return; }
                    button.down = false;
                    button.holdDuration = 2000;
                    if (drawer.item !== saved) { fail("Reopening replaced Settings"); return; }
                    if (HardwareSnapshot.checkedAt !== checked) { fail("Reopening repeated fresh snapshot"); return; }
                    button.holdDuration = 240;
                    button.down = true; step = 4; ticks = 0;
                } else if (step === 4 && ticks > 8) {
                    if (activations !== 1 || executions !== 1 || lastAction !== "poweroff") { fail("Hold did not execute exactly once"); return; }
                    button.down = false; button.holdDuration = 2000;
                    const snapshot = Object.assign({}, HardwareSnapshot.data);
                    snapshot.monitors = [
                        {name:"eDP-2", label:"Laptop", width:1920, height:1080, refreshRate:60, scale:1.25, x:0, disabled:false, availableModes:["1920x1080@60.00Hz"], ddcBus:null},
                        {name:"DP-3", label:"Dell S2722DC", width:2560, height:1440, refreshRate:60, scale:1, x:1536, disabled:false, availableModes:["2560x1440@60.00Hz"], ddcBus:19}];
                    snapshot.ddcBuses = [19]; snapshot.primary = "DP-3";
                    HardwareSnapshot.data = snapshot;
                    AttentionData.forecast = {current:{icon:"cloud-sun", temperature:29, description:"Partly cloudy"}};
                    saved.page = "display"; step = 3; ticks = 0;
                } else if (step === 3 && ticks > 4) {
                    const display = find(saved, "display-page");
                    const remember = find(saved, "display-save");
                    if (!display || !remember || !remember.enabled) { fail("Display layout control missing"); return; }
                    safeMachine.snapshot = HardwareSnapshot.data;
                    display.machine = safeMachine;
                    remember.clicked();
                    if (lastAction !== "display-save") { fail("Remember layout did not use display backend"); return; }
                    canvas.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/settings-displays.png"))) { fail("Capture failed"); return; }
                        saved.page = "cpu";
                        safeMachine.snapshot = {hardware:{boost:"1", boostControlError:""}};
                        test.step = 5; test.ticks = 0; test.start();
                    });
                    stop();
                } else if (step === 5) {
                    const details = find(saved, "hardware-details");
                    if (!details) return;
                    details.machine = safeMachine;
                    step = 6; ticks = 0;
                } else if (step === 6 && ticks > 1) {
                    const toggle = find(saved, "cpu-boost-toggle");
                    if (!toggle || !toggle.enabled || toggle.text !== "Disable CPU boost") { fail("Boost control did not use kernel state"); return; }
                    toggle.clicked();
                    if (lastAction !== "cpu-boost" || lastValue !== "off") { fail("Boost toggle did not disable boost"); return; }
                    step = 7; ticks = 0;
                } else if (step === 7 && ticks > 1) {
                    const toggle = find(saved, "cpu-boost-toggle");
                    if (toggle.text !== "Enable CPU boost") { fail("Boost state did not refresh after action"); return; }
                    toggle.clicked();
                    if (lastValue !== "on") { fail("Boost toggle did not enable boost"); return; }
                    safeMachine.snapshot = {hardware:{boost:"1", boostControlError:"Install helper"}};
                    step = 8; ticks = 0;
                } else if (step === 8 && ticks > 1) {
                    if (find(saved, "cpu-boost-toggle").enabled) { fail("Boost control enabled without installed helper"); return; }
                    console.log("SETTINGS PASS: retained drawer, snapshot reuse, hidden hold cancellation, displays, weather, state-driven CPU boost toggle");
                    stop(); Qt.quit();
                }
            }
        }
    }
}
