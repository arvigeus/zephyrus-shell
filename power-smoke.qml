import QtQuick
import Quickshell
import "core"
import "settings"

ShellRoot {
    FloatingWindow {
        implicitWidth: 490; implicitHeight: 500
        color: Theme.background
        Machine { id: machine }
        PowerSection { id: section; x: 16; y: 16; width: 458; machine: machine }
        Connections {
            target: verifier.loader ? verifier.loader.item : null
            function onBatteriesChanged() { verifier.readCount++; }
        }
        Timer {
            id: verifier
            interval: 80; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property var firstItem: null
            readonly property var loader: section.children.find(child => child.objectName === "batteryDetailsLoader") || null
            property int readCount: 0
            property int previousReads: 0
            function fail(message) { console.error("POWER FAIL", message); stop(); Qt.quit(); }
            onTriggered: {
                if (++ticks > 100) { fail("Timed out at step " + step); return; }
                if (!loader) { fail("Missing details loader"); return; }
                if (step === 0) {
                    if (machine.busy) return;
                    if (loader.active || loader.item) { fail("Details created while collapsed"); return; }
                    section.expanded = true; step++; ticks = 0;
                } else if (step === 1) {
                    if (!loader.item || !loader.item.loaded || loader.item.loading) return;
                    if (loader.item.error) { fail(loader.item.error); return; }
                    firstItem = loader.item;
                    previousReads = readCount;
                    machine.refresh(); step++; ticks = 0;
                } else if (step === 2) {
                    if (machine.busy || loader.item.loading || readCount === previousReads) return;
                    if (loader.item !== firstItem) { fail("Refresh replaced the card"); return; }
                    previousReads = readCount; step++; ticks = 0;
                } else if (step === 3) {
                    if (loader.item.loading || readCount === previousReads) return;
                    section.expanded = false; step++; ticks = 0;
                } else if (step === 4) {
                    if (loader.item || loader.active) { fail("Collapsing retained details"); return; }
                    section.expanded = true; step++; ticks = 0;
                } else if (step === 5) {
                    if (!loader.item || !loader.item.loaded || loader.item.loading) return;
                    if (loader.item.error) { fail(loader.item.error); return; }
                    if (loader.item.batteries.length === 0 && loader.item.implicitHeight <= 0) { fail("No battery state is empty"); return; }
                    section.grabToImage(result => {
                        const target = Paths.file("tests/artifacts/battery-details.png");
                        if (!result.saveToFile(target)) { fail("Could not save card preview"); return; }
                        console.log("POWER PASS: lazy expansion, real readings, in-place and periodic refresh, collapse, reopen, and capture");
                        Qt.quit();
                    });
                    stop();
                }
            }
        }
    }
}
