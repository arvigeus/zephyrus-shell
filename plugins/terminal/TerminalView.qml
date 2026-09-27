import QtQuick
import Quickshell
import QMLTermWidget

Item {
    id: root
    signal commandSubmitted()
    property bool hasInput: false
    function forceTerminalFocus() { terminal.forceActiveFocus(); }
    function copySelection() { terminal.copyClipboard(); }
    function pasteClipboard() { hasInput = true; terminal.pasteClipboard(); }
    QMLTermWidget {
        id: terminal
        anchors.fill: parent
        font: Qt.font({family: "Noto Sans Mono", pointSize: 11, styleHint: Font.TypeWriter, fixedPitch: true})
        colorScheme: "WhiteOnBlack"
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.hasInput) root.commandSubmitted();
                root.hasInput = false;
            } else if (event.text && event.text.trim()) {
                root.hasInput = true;
            }
            event.accepted = false;
        }
        session: QMLTermSession {
            initialWorkingDirectory: Quickshell.env("HOME") || "/"
            shellProgram: Quickshell.env("SHELL") || "/bin/bash"
            Component.onCompleted: startShellProgram()
        }
    }
}
