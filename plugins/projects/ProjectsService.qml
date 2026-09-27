import QtQuick
import "../../services"

Worker {
    objectName: "projectsService"
    backend: "plugins/projects/backend.py"
    serviceName: "Projects"
    timeout: 650000
}
