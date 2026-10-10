import QtQuick
import "../../services"

Worker {
    objectName: "projectsService"
    backend: "modules/projects/backend.py"
    serviceName: "Projects"
    timeout: 650000
}
