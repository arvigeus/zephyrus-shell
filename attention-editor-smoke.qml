import QtQuick
import Quickshell
import "attention"
import "core"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 800
        color: Theme.background
        Rectangle {
            id: panel
            x: 20; y: 72; width: 1240; height: 600
            color: Theme.background
            border.color: Theme.border
            EntryEditor {
                id: editor
                anchors.fill: parent
                Component.onCompleted: begin("VTODO", {summary: "Review report", description: "Check the figures before Friday.", due: "2026-10-02", list_slug: "tasks", editable: true, href: "https://cloud.example/tasks/item.ics", etag: "abc"}, "", [
                    {name: "Tasks", slug: "tasks", writable: true, components: ["VTODO"], tasks_enabled: true}
                ])
            }
        }
        Timer {
            interval: 1500; running: true
            onTriggered: panel.grabToImage(result => { console.log("EDITOR_CAPTURE", result.saveToFile("/tmp/attention-editor-smoke.png")); Qt.quit(); })
        }
    }
}
