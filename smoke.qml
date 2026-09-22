// Integration harness: only run on a private D-Bus session (scripts/check-wayland.sh).
import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "shell"

ShellRoot {
    Variants {
        model: Quickshell.screens
        ShellScreen { required property var modelData; screen: modelData }
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
                if (!Plugins.find("apps")) throw new Error("Apps plugin was not discovered");
                ShellState.openPlugin("apps");
                if (ShellState.panel !== "module") throw new Error("Module did not replace drawer");
                break;
            case 2:
                ShellState.toggle("left");
                if (ShellState.panel || ShellState.pluginId) throw new Error("Desktop did not close module");
                ShellState.openPlugin("apps");
                ShellState.backToSpaces();
                if (ShellState.panel !== "left" || ShellState.pluginId) throw new Error("Module back failed");
                ShellState.openPlugin("apps");
                ShellState.toggle("right");
                if (ShellState.pluginId) throw new Error("Switching panels retained module");
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
                ShellState.close();
                if (Attention.count !== 0 || ShellState.panel || ShellState.pluginId) throw new Error("State cleanup failed");
                console.log("SMOKE PASS: panels, plugin discovery, notifications and cleanup");
                Qt.quit();
            }
        }
    }
}
