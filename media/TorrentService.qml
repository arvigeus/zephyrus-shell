import QtQuick
import "../services"

Worker {
    backend: "media/torrent_backend.py"
    serviceName: "qBittorrent"
    timeout: 600000
}
