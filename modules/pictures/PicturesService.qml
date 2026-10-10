import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "picturesService"
    backend: "modules/pictures/backend.py"
    serviceName: "Pictures"
}
