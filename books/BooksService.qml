import QtQuick
import Quickshell
import "../services"

JobWorker {
    objectName: "booksService"
    backend: "books/backend.py"
    serviceName: "Books"
}
