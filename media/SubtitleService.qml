import QtQuick
import "../services"

Worker {
    backend: "media/subtitle_backend.py"
    serviceName: "Subtitles"
    startOnDemand: true
    timeout: 150000
}
