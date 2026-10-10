import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../settings"
import "../../shell"

Scope {
    FloatingWindow {
        id: window
        implicitWidth: 480; implicitHeight: 340
        color: Theme.background
        Item {
            id: canvas
            anchors.fill: parent
            StatusPill { id: pill; x: 12; y: 12 }
            StatusPill { id: secondPill; opacity: 0 }
            WifiPage { id: page; visible: false; anchors.fill: parent; anchors.topMargin: 60; anchors.leftMargin: 12; anchors.rightMargin: 12; compact: true }
        }
        Process {
            id: denyNext
            command: ["python3", Paths.file("tests/fixtures/warp_host.py"), "deny-next"]
            onExited: { Warp.run("disconnect"); test.step = 4; }
        }
        Timer {
            id: test
            interval: 80; running: true; repeat: true
            property int ticks: 0
            property double started: Date.now()
            property int step: 0
            property bool sawConnecting: false
            function find(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) { const result = find(child, name); if (result) return result; }
                return null;
            }
            function fail(message) { console.error("WARP FAIL", message); stop(); Qt.quit(); }
            onTriggered: {
                if (++ticks > 290) { fail("Timeout at step " + step); return; }
                const row = find(page, "warp-network-row");
                const service = Warp;
                if (!row || !service.available) return;
                const toggle = find(row, "warp-network-toggle");
                const icon = find(row, "warp-network-icon");
                const indicator = find(pill, "warp-status-icon");
                if (step === 0) {
                    if (Date.now() - started < 11000) return;
                    if (service.state !== "off" || service.enabled || indicator.visible) { fail("Initial idle state"); return; }
                    if (row.connection !== service) { fail("List does not share bar state"); return; }
                    page.visible = true;
                    if (icon.opacity !== 0.55 || find(row, "warp-network-status").visible) { fail("Disconnected row"); return; }
                    toggle.clicked(); step++; return;
                } else if (step === 1) {
                    if (service.state === "connecting") sawConnecting = true;
                    if (service.state !== "connected" || service.requestActive) return;
                    if (!sawConnecting || icon.opacity !== 1 || !indicator.visible || !find(secondPill, "warp-status-icon").visible) { fail("Delayed event did not update list and both bars"); return; }
                    canvas.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/warp-capture.png"))) { fail("Capture"); return; }
                        page.visible = false;
                        service.run("disconnect"); step++; test.start();
                    });
                    stop();
                } else if (step === 2) {
                    if (service.state !== "off" || service.requestActive) return;
                    if (indicator.visible) { fail("Disconnect with closed Settings retained indicator"); return; }
                    // Start outside Settings and reopen only after the event.
                    service.run("connect"); step++;
                } else if (step === 3) {
                    if (service.state !== "connected" || service.requestActive) return;
                    if (!indicator.visible) { fail("Closed Settings missed connect"); return; }
                    page.visible = true;
                    if (icon.opacity !== 1 || !toggle.text.startsWith("Disconnect")) { fail("Reopened list lost shared state"); return; }
                    denyNext.running = true; step = -1;
                } else if (step === 4) {
                    if (service.requestActive || !service.error) return;
                    if (!service.error.startsWith("Test policy denied connection") || find(row, "warp-network-error").text !== service.error || !indicator.visible) { fail("Failed action did not preserve connection/error"); return; }
                    service.apply({ok: true, state: "connected"});
                    if (!service.error) { fail("Passive event erased action error"); return; }
                    icon.clicked(); step = 5;
                } else if (step === 5) {
                    if (service.state !== "off" || service.requestActive) return;
                    if (service.error || indicator.visible || icon.opacity !== 0.55) { fail("Final off state"); return; }
                    console.log("WARP PASS: delayed connection events, shared multi-output state, closed Settings, on-demand streams, inline errors");
                    stop(); Qt.quit();
                }
            }
        }
    }
}
