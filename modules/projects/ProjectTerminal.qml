import QtQuick
import QMLTermWidget
import "../../core"

// Runs a prepared setup script; destroying this item ends its terminal session.
Item {
    id: root
    required property string projectPath
    required property string scriptPath

    QMLTermWidget {
        anchors.fill: parent
        font: Qt.font({family: Theme.monospaceFont, pointSize: Theme.monospaceFontSize,
                       styleHint: Font.TypeWriter, fixedPitch: true})
        colorScheme: "WhiteOnBlack"
        session: QMLTermSession {
            initialWorkingDirectory: root.projectPath
            shellProgram: "/bin/bash"
            shellProgramArgs: [root.scriptPath]
            Component.onCompleted: startShellProgram()
        }
    }
}
