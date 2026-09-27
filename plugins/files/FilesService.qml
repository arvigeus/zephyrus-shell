import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "filesService"
    backend: "plugins/files/backend.py"
    serviceName: "Files"
    readonly property string homePath: Quickshell.env("HOME") || "/"
}
