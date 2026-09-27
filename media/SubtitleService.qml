import QtQuick
import "../services"

Worker {
    backend: "media/subtitle_backend.py"
    serviceName: "Subtitles"
    timeout: 150000
}
