import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "radioService"
    backend: "modules/radio/backend.py"
    serviceName: "Radio"
}
