import QtQuick
import Quickshell
import "../../services"

Worker {
    objectName: "gamesService"
    backend: "modules/games/backend.py"
    serviceName: "Games"
}
