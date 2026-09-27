import QtQuick
import Quickshell
import "../services"

Worker {
    objectName: "mediaService"
    backend: "media/backend.py"
    serviceName: "Media"
}
