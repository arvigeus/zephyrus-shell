import QtQuick
import Quickshell
import "../services"

Worker {
    objectName: "picturesService"
    backend: "pictures/backend.py"
    serviceName: "Pictures"
}
