import QtQuick
import "../services"

Worker {
    objectName: "clipboardService"
    backend: "clipboard/backend.py"
    serviceName: "Clipboard"
}
