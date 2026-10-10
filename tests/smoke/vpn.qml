import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../settings"

Scope {
    FloatingWindow {
        implicitWidth: 480; implicitHeight: 360
        color: Theme.background
        QtObject {
            id: safeWarp
            property string state: "off"
            property bool enabled: false
            property bool available: true
            property bool transitioning: false
            property string label: ""
            property string error: ""
            function toggle() {}
        }
        Loader {
            id: loader
            objectName: "vpn-smoke-page"
            anchors.fill: parent; anchors.margins: 16
            sourceComponent: WifiPage { compact: true }
        }
        Process {
            id: boundary
            property string action: ""
            command: ["python3", Paths.file("tests/fixtures/vpn_host.py"), action]
            onExited: {
                if (action === "deny-next") { test.find(loader.item, "vpn-network-toggle").clicked(); test.step = 4; }
                else { loader.item.vpnService.refresh(); test.step = 5; }
            }
        }
        Timer {
            id: test
            interval: 80; running: true; repeat: true
            property int step: 0
            property int ticks: 0
            property bool sawBusy: false
            function fail(message) { console.error("VPN FAIL", message); stop(); Qt.quit(); }
            function find(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (const child of item.children || []) { const result = find(child, name); if (result) return result; }
                return null;
            }
            onTriggered: {
                if (++ticks > 180) { fail("Timeout at step " + step); return; }
                if (step === 2) { loader.active = true; step = 3; return; }
                if (!loader.item) return;
                const service = loader.item.vpnService;
                const warpRow = find(loader.item, "warp-network-row");
                if (warpRow) warpRow.connection = safeWarp;
                if (!service.loaded || service.refreshing) return;
                const row = find(loader.item, "vpn-network-row");
                const toggle = find(row, "vpn-network-toggle");
                const icon = find(row, "vpn-network-icon");
                if (step === 0) {
                    if (!row || !service.available || row.profile.name !== "Home VPN" || icon.iconName !== "shield-lock") { fail("Discovered profile/icon missing"); return; }
                    if (row.profile.active || icon.opacity !== 0.55) { fail("Idle profile state"); return; }
                    icon.clicked(); step = 1;
                } else if (step === 1) {
                    if (service.busy) { sawBusy = true; if (toggle.enabled) fail("Action enabled while connecting"); return; }
                    if (!row.profile.connected) return;
                    if (!sawBusy || icon.opacity !== 1) { fail("Connection transition/state missing"); return; }
                    loader.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/vpn-capture.png"))) { fail("Capture failed"); return; }
                        loader.active = false; test.step = 2; test.start();
                    });
                    stop();
                } else if (step === 3) {
                    if (!row || !row.profile.connected || !toggle.text.startsWith("Disconnect")) { fail("Tunnel did not survive page destruction"); return; }
                    boundary.action = "deny-next"; boundary.running = true; step = -1;
                } else if (step === 4) {
                    if (service.busy || !service.error) return;
                    if (!row.profile.connected || !find(row, "vpn-network-error").text.includes("denied permission")) { fail("Inline denial lost active state"); return; }
                    boundary.action = "remove-config"; boundary.running = true; step = -1;
                } else if (step === 5) {
                    if (!row || !row.profile.error.includes("removed")) return;
                    if (!toggle.enabled) { fail("Removed active profile cannot disconnect"); return; }
                    icon.clicked(); step = 6;
                } else if (step === 6) {
                    if (service.busy || service.profiles.length) return;
                    console.log("VPN PASS: folder discovery, Lucide icon, transitions, owned page lifecycle, inline denial, removed-config disconnect");
                    stop(); Qt.quit();
                }
            }
        }
    }
}
