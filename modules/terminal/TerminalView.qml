import QtQuick
import Quickshell
import QMLTermWidget
import "../../core"

Item {
    id: root
    signal finished()
    property bool hasInput: false
    readonly property string title: shellSession.title
    function processId() { return shellSession.getShellPID(); }
    function scrollback() { return shellSession.history; }
    function applyColors() {
        // Public native slots recolor the existing screen without touching its PTY.
        terminal.setBackgroundColor(Theme.background);
        terminal.setForegroundColor(Theme.text);
        terminal.fillColor = Theme.background;
    }
    function runCommand(command) {
        if (shellSession.hasActiveProcess)
            return "Wait for the current program to finish before running a saved command.";
        if (hasInput)
            return "Submit your current input, or press Ctrl+U to clear it first.";
        shellSession.sendText(command + "\n");
        forceTerminalFocus();
        return "";
    }
    function forceTerminalFocus() { terminal.forceActiveFocus(); }
    function copySelection() { terminal.copyClipboard(); }
    function pasteClipboard() { hasInput = true; terminal.pasteClipboard(); }
    QMLTermWidget {
        id: terminal
        objectName: "terminalSurface"
        anchors.fill: parent
        font: Qt.font({family: Theme.monospaceFont, pointSize: Theme.monospaceFontSize, styleHint: Font.TypeWriter, fixedPitch: true})
        colorScheme: Theme.mode === "dark" ? "DarkPastels" : "BlackOnWhite"
        onColorSchemeChanged: root.applyColors()
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && [Qt.Key_U, Qt.Key_C].includes(event.key)) {
                root.hasInput = false;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.hasInput = false;
            } else if (event.text && event.text.trim()) {
                root.hasInput = true;
            }
            event.accepted = false;
        }
        session: QMLTermSession {
            id: shellSession
            initialWorkingDirectory: Quickshell.env("HOME") || "/"
            shellProgram: Quickshell.env("SHELL") || "/bin/bash"
            Component.onCompleted: startShellProgram()
            onFinished: root.finished()
        }
    }
    Connections {
        target: Theme
        function onBackgroundChanged() { root.applyColors(); }
        function onTextChanged() { root.applyColors(); }
    }
    Component.onCompleted: applyColors()
}
