import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "radioService"
    backend: "plugins/radio/backend.py"
    serviceName: "Radio"
}
