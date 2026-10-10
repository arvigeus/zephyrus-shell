import QtQuick
import Quickshell
import "../../services"

JobWorker {
    objectName: "musicService"
    backend: "modules/music/backend.py"
    serviceName: "Music"
}
