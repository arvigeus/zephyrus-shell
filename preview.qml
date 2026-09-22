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
            Action { z: 1; x: 14; y: 12; text: "Desktop"; iconName: "monitor"; onClicked: ShellState.toggle("left") }
            Action { z: 1; anchors.horizontalCenter: parent.horizontalCenter; y: 12; text: "Mon, Sep 21   ·   10:45"; onClicked: ShellState.toggle("center") }
            StatusPill { z: 1; anchors.right: parent.right; anchors.rightMargin: 14; y: 12; onClicked: ShellState.toggle("right") }
            Loader {
                x: 0; y: 0; width: parent.width; height: parent.height
                active: ShellState.panel === "module"
                sourceComponent: ModuleOverlay { readyToLoad: !left.showing && !right.showing }
            }
            MouseArea {
                z: 2
                visible: ShellState.panel === "left" || ShellState.panel === "right"
                x: ShellState.panel === "left" ? left.width : 0
                width: canvas.width - (ShellState.panel === "left" ? left.width : right.width)
                height: canvas.height
                acceptedButtons: Qt.AllButtons
                onClicked: ShellState.close()
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
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter; y: 72; width: Math.min(850, canvas.width - 28); height: Math.min(canvas.width < 728 ? 700 : 460, canvas.height - 90)
                active: ShellState.panel === "center"
                sourceComponent: AttentionPanel {}
            }
        }
        Timer {
            property int step: 0
            interval: 1200; repeat: true; running: Quickshell.env("DRAWER_SHELL_CAPTURE") === "1"
            onTriggered: {
                const panels = ["", "left", "module", "right", "center", "right", "right", "right", "right", "right", "right", "right"];
                const target = Paths.file("tests/artifacts/preview-" + step + ".png");
                canvas.grabToImage(result => {
                    console.log("CAPTURE", target, result.saveToFile(target));
                    step++;
                    if (step === panels.length) { stop(); finish.start(); return; }
                    ShellState.panel = panels[step];
                    ShellState.pluginId = step === 2 ? "apps" : "";
                    if (step >= 5) Qt.callLater(() => { if (right.item) { right.item.page = ["wifi", "bluetooth", "display", "cpu", "gpu", "memory", ""][step - 5]; right.item.expandSections = step === 11; } });
                });
            }
        }
        Timer { id: finish; interval: 500; onTriggered: Qt.quit() }
    }
}
