import QtQuick
import Quickshell
import "../services"

Worker {
    objectName: "gamesService"
    backend: "games/backend.py"
    serviceName: "Games"
}
