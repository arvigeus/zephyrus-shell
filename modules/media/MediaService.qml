import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "mediaService"
    backend: "modules/media/backend.py"
    serviceName: "Media"
}
