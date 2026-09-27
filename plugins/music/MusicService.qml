import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "musicService"
    backend: "plugins/music/backend.py"
    serviceName: "Music"
}
