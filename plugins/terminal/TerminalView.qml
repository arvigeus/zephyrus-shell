import QtQuick
import Quickshell
import QMLTermWidget

Item {
    function forceTerminalFocus() { terminal.forceActiveFocus(); }
    function copySelection() { terminal.copyClipboard(); }
    function pasteClipboard() { terminal.pasteClipboard(); }
    QMLTermWidget {
        id: terminal
        anchors.fill: parent
        font: Qt.font({family: "Noto Sans Mono", pointSize: 11, styleHint: Font.TypeWriter, fixedPitch: true})
        colorScheme: "WhiteOnBlack"
        session: QMLTermSession {
            initialWorkingDirectory: Quickshell.env("HOME") || "/"
            shellProgram: Quickshell.env("SHELL") || "/bin/bash"
            Component.onCompleted: startShellProgram()
        }
    }
}
