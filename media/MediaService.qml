import QtQuick
import Quickshell.Io
import "../core"

Item {
    id: root
    objectName: "mediaService"
    visible: false
    property int serial: 0
    property var callbacks: ({})
    signal failed(string message)
    function request(op, args, callback) {
        const id = ++serial;
        callbacks[id] = callback;
        worker.write(JSON.stringify(Object.assign({}, args || {}, {id: id, op: op})) + "\n");
        return id;
    }
    Process {
        id: worker
        command: ["python3", "-u", Paths.file("media/backend.py")]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const response = JSON.parse(data);
                    const callback = root.callbacks[response.id];
                    delete root.callbacks[response.id];
                    if (callback) callback(response.result, response.error || "");
                } catch (error) { root.failed("Could not read a media response."); }
            }
        }
        onExited: (code, status) => {
            const pending = root.callbacks;
            root.callbacks = ({});
            for (const key in pending) pending[key](null, "Media service stopped. Close and reopen this module.");
        }
    }
    Component.onDestruction: { worker.running = false; }
}
