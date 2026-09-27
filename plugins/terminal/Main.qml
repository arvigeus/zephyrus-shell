import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../files"
import "../../core"
import "../../widgets"

FocusScope {
    id: root
    property var host
    function activate() {
        if (terminalLoader.item) terminalLoader.item.forceTerminalFocus();
    }
    function restartShell() {
        terminalLoader.active = false;
        restartTimer.restart();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Shell"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 15
                Layout.fillWidth: true
            }

            IconButton {
                iconName: "copy"
                text: "Copy selection"
                enabled: terminalLoader.item !== null
                onClicked: if (terminalLoader.item) terminalLoader.item.copySelection()
            }
            IconButton {
                iconName: "file-text"
                text: "Paste from clipboard"
                enabled: terminalLoader.item !== null
                onClicked: if (terminalLoader.item) terminalLoader.item.pasteClipboard()
            }
            IconButton {
                iconName: "rotate-ccw"
                text: "Restart shell"
                onClicked: root.restartShell()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background
            radius: Theme.radius
            border.color: Theme.border
            border.width: 1

            Loader {
                id: terminalLoader
                anchors.fill: parent
                anchors.margins: 10
                active: true
                source: "TerminalView.qml"
                onLoaded: Qt.callLater(root.activate)
            }
            Connections {
                target: terminalLoader.item
                function onCommandSubmitted() {
                    if (root.host) root.host.requestKeepRunning("terminal", true);
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                visible: terminalLoader.status === Loader.Error
                Label { text: "The embedded terminal is unavailable."; color: Theme.muted }
                Action {
                    text: "Open system terminal"; iconName: "terminal"
                    onClicked: fallback.request("terminal", {}, (result, error) => {
                        fallbackMessage.text = error || "";
                        if (!error && root.host) root.host.close();
                    })
                }
                Label { id: fallbackMessage; color: Theme.danger; visible: !!text }

            }
        }
    }

    FilesService { id: fallback }

    Timer {
        id: restartTimer
        interval: 1
        onTriggered: terminalLoader.active = true
    }

    Component.onCompleted: Qt.callLater(activate)
}
