// Integration harness: only run on a private D-Bus session (tests/native/wayland.sh).
import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../shell"

Scope {
    id: root
    property ModuleLoader modules: ModuleLoader { readyToLoad: false; anchors.fill: parent }
    Variants {
        model: Quickshell.screens
        ShellScreen { required property var modelData; screen: modelData; modules: root.modules }
    }
    Process {
        id: notification
        command: ["notify-send", "Zephyrus Shell test", "Notification delivery verified"]
    }
    Timer {
        property int step: 0
        interval: 1500; running: true; repeat: true
        onTriggered: {
            switch (step++) {
            case 0: ShellState.toggle("left"); break;
            case 1:
                if (!Modules.find("apps")) throw new Error("Apps plugin was not discovered");
                ShellState.openModule("apps");
                if (ShellState.panel !== "module") throw new Error("Module did not replace drawer");
                break;
            case 2:
                ShellState.toggle("left");
                if (ShellState.panel !== "left" || ShellState.moduleId !== "apps") throw new Error("Spaces did not preserve module");
                ShellState.showDesktop();
                if (ShellState.panel || ShellState.moduleId) throw new Error("Desktop did not reveal session");
                ShellState.openModule("apps");
                ShellState.toggle("right");
                if (ShellState.moduleId !== "apps") throw new Error("Settings discarded module");
                break;
            case 3: notification.running = true; break;
            case 4:
                if (Attention.count !== 1) throw new Error("Notification delivery failed");
                ShellState.toggle("center");
                break;
            case 5:
                Attention.clear();
                ShellState.toggle("left");
                ShellState.openProfile({name: "Profile test", username: "test", home: "/home/test", avatar: ""});
                if (ShellState.panel !== "profile") throw new Error("Profile did not replace drawer");
                break;
            case 6:
                ShellState.showDesktop();
                if (Attention.count !== 0 || ShellState.panel || ShellState.moduleId) throw new Error("State cleanup failed");
                console.log("SMOKE PASS: panels, plugin discovery, notifications and cleanup");
                Qt.quit();
            }
        }
    }
}
