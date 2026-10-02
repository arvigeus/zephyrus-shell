import QtQuick
import "../../services"

Worker {
    objectName: "clipboardService"
    backend: "plugins/clipboard/backend.py"
    serviceName: "Clipboard"
}
