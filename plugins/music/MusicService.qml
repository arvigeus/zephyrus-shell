import QtQuick
import Quickshell
import "../../services"

JobWorker {
    objectName: "musicService"
    backend: "plugins/music/backend.py"
    serviceName: "Music"
}
