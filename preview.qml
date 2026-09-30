import QtQuick
import Quickshell
import "core"
import "widgets"
import "drawers"
import "attention"
import "shell"

ShellRoot {
    Component.onCompleted: { const ready = Profiles.loaded; const hardware = HardwareSnapshot.data; }
    FloatingWindow {
        id: window
        title: "Zephyrus Shell · component preview"
        implicitWidth: 1280; implicitHeight: 800
        color: Theme.background
        Backdrop {
            id: canvas
            anchors.fill: parent
            Action { z: 1; x: 14; y: 12; text: "Spaces"; iconName: "grid-vertical"; onClicked: ShellState.toggle("left") }
            Action {
                z: 1; anchors.horizontalCenter: parent.horizontalCenter; y: 12
                text: Qt.formatDateTime(previewClock.date, "ddd, MMM d   ·   HH:mm") + (Attention.count ? "   • " + Attention.count : "")
                onClicked: ShellState.toggle("center")
                SystemClock { id: previewClock; precision: SystemClock.Minutes }
            }
            StatusPill { z: 1; anchors.right: parent.right; anchors.rightMargin: 14; y: 12; onClicked: ShellState.toggle("right") }
            ModuleLoader {
                id: modulePreview
                x: 0; y: 0; width: parent.width; height: parent.height
                readyToLoad: !left.showing && !right.showing
            }
            MouseArea {
                z: 2
                visible: ShellState.panel === "left" || ShellState.panel === "right"
                x: ShellState.panel === "left" ? left.width : 0
                width: canvas.width - (ShellState.panel === "left" ? left.width : right.width)
                height: canvas.height
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.dismissPanel()
            }
            Loader {
                z: 3; anchors.centerIn: parent; width: Math.min(380, canvas.width - 32); height: 320
                active: ShellState.panel === "profile" && !left.showing && !right.showing
                sourceComponent: UserProfilePanel {}
            }
            DrawerSlide {
                id: left
                z: 2; x: 0; y: 0; width: Math.min(390, canvas.width); height: parent.height
                side: "left"
                opened: ShellState.panel === "left"
                contentSource: Qt.resolvedUrl("drawers/LibraryDrawer.qml")
            }
            DrawerSlide {
                id: right
                z: 2; anchors.right: parent.right; y: 0; width: Math.min(490, canvas.width); height: parent.height
                side: "right"
                opened: ShellState.panel === "right"
                contentSource: Qt.resolvedUrl("drawers/ControlDrawer.qml")
            }
            MouseArea {
                visible: ShellState.panel === "center"
                x: 0; y: Theme.pillHeight; width: canvas.width; height: Math.max(0, centerPreview.y - y)
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.dismissPanel()
            }
            MouseArea {
                visible: ShellState.panel === "center"
                x: 0; y: centerPreview.y; width: centerPreview.x; height: centerPreview.height
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.dismissPanel()
            }
            MouseArea {
                visible: ShellState.panel === "center"
                x: centerPreview.x + centerPreview.width; y: centerPreview.y
                width: canvas.width - x; height: centerPreview.height
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.dismissPanel()
            }
            MouseArea {
                visible: ShellState.panel === "center"
                x: 0; y: centerPreview.y + centerPreview.height
                width: canvas.width; height: canvas.height - y
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.dismissPanel()
            }
            Loader {
                id: centerPreview
                anchors.horizontalCenter: parent.horizontalCenter; y: 72; width: Math.min(1240, canvas.width - 28); height: Math.min(canvas.width < 900 ? 700 : 600, canvas.height - 90)
                active: ShellState.panel === "center"
                sourceComponent: AttentionPanel {}
            }
        }
        Timer {
            property int step: 0
            property int attentionWait: 0
            property int appsWait: 0
            interval: 1200; repeat: true; running: Quickshell.env("DRAWER_SHELL_CAPTURE") === "1"
            onTriggered: {
                if (step === 2 && appsWait++ < 15 && (!modulePreview.item
                        || !modulePreview.item.currentModule || !modulePreview.item.currentModule.catalogReady))
                    return;
                if (step === 4 && centerPreview.item && attentionWait++ < 15
                        && ((centerPreview.item.forecast === null && centerPreview.item.weatherError === "")
                            || (centerPreview.item.cloud.state === "loading" && centerPreview.item.cloudError === "")))
                    return;
                const panels = ["", "left", "module", "right", "center", "right", "right", "right", "right", "right", "right", "right"];
                const target = Paths.file("tests/artifacts/preview-" + step + ".png");
                canvas.grabToImage(result => {
                    console.log("CAPTURE", target, result.saveToFile(target));
                    step++;
                    if (step === panels.length) { stop(); finish.start(); return; }
                    if (step === 2) ShellState.openPlugin("apps");
                    else if (step === 3) { ShellState.close(); ShellState.toggle("right"); }
                    else ShellState.panel = panels[step];
                    if (step >= 5) Qt.callLater(() => { if (right.item) {
                        right.item.page = ["", "", "display", "cpu", "gpu", "system", ""][step - 5];
                        right.item.wifiExpanded = step === 5;
                        right.item.bluetoothExpanded = step === 6;
                        right.item.expandSections = step === 11;
                    } });
                });
            }
        }
        Timer { id: finish; interval: 500; onTriggered: Qt.quit() }
    }
}
