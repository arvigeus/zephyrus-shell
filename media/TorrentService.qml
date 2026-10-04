import QtQuick
import "../services"

Worker {
    backend: "media/torrent_backend.py"
    serviceName: "qBittorrent"
    startOnDemand: true
    timeout: 600000
}
