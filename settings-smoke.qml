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
            function run(name, value) { test.executions++; test.lastAction = name; }
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
                    if (drawer.item !== saved || HardwareSnapshot.checkedAt !== checked) { fail("Reopening replaced Settings or repeated fresh snapshot"); return; }
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
                    canvas.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/settings-displays.png"))) { fail("Capture failed"); return; }
                        console.log("SETTINGS PASS: retained real drawer, fresh snapshot reuse, hidden hold cancellation, display page and shared weather");
                        Qt.quit();
                    });
                    stop();
                }
            }
        }
    }
}
