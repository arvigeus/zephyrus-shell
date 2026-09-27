import QtQuick
import Quickshell
import "../services"

Worker {
    objectName: "booksService"
    backend: "books/backend.py"
    serviceName: "Books"
}
