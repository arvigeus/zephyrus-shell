import QtQuick
import QMLTermWidget

Item {
    id: root
    required property string projectPath
    required property string scriptPath
    function focusTerminal() { terminal.forceActiveFocus(); }
    function copySelection() { terminal.copyClipboard(); }
    function pasteClipboard() { terminal.pasteClipboard(); }

    QMLTermWidget {
        id: terminal
        anchors.fill: parent
        font: Qt.font({family: "Noto Sans Mono", pointSize: 11,
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
