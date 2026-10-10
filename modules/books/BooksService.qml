import QtQuick
import Quickshell
import "../../services"

JobWorker {
    objectName: "booksService"
    backend: "modules/books/backend.py"
    serviceName: "Books"
}
