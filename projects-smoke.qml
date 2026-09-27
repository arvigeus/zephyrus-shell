import QtQuick
import Quickshell
import "plugins/projects" as Projects

ShellRoot {
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 700
        Projects.Main {
            id: project
            anchors.fill: parent
        }
        Loader {
            id: terminalCheck
            active: false
            width: 400; height: 200
            sourceComponent: Projects.ProjectTerminal {
                projectPath: Quickshell.env("HOME") || "/"
                scriptPath: "/bin/true"
            }
        }
        Timer {
            interval: 400
            running: true
            repeat: true
            property int step: 0
            onTriggered: {
                if (step === 0) project.showForm("create");
                else if (step === 1) {
                    project.createdPath = Quickshell.env("HOME") || "/";
                    project.setupScript = "/bin/true";
                }
                else if (step === 2) project.showForm("clone");
                else if (step === 3) terminalCheck.active = true;
                else if (step === 4) project.showGlobalAction("globalSpace");
                else { console.log("PROJECT DIALOGS PASS"); Qt.quit(); }
                step++;
            }
        }
    }
}
