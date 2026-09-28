import QtQuick
import Quickshell.Io
import "../core"

// One owned JSON-lines process per module. Every request settles exactly once.
Item {
    id: root
    visible: false
    required property string backend
    property string serviceName: "Module"
    property int timeout: 90000
    property int serial: 0
    property var callbacks: ({})
    property bool stopped: false
    signal failed(string message)

    function settle(id, result, error) {
        const pending = callbacks[id];
        delete callbacks[id];
        if (!pending) return;
        try { pending.callback(result, error || ""); }
        catch (exception) {
            console.error(serviceName + " response handler failed:", exception);
            failed(serviceName + " could not display that response. Retry the request.");
        }
    }
    function failPending(message) {
        for (const id of Object.keys(callbacks)) settle(id, null, message);
    }
    function request(op, args, callback, timeoutMs) {
        const id = ++serial;
        callbacks[id] = {callback: callback || function() {},
                         deadline: timeoutMs === 0 ? Infinity : Date.now() + (timeoutMs || timeout)};
        if (stopped) {
            settle(id, null, serviceName + " service stopped. Close and reopen this module.");
            return id;
        }
        worker.write(JSON.stringify(Object.assign({}, args || {}, {id: id, op: op})) + "\n");
        return id;
    }
    Timer {
        interval: 1000; repeat: true; running: !root.stopped
        onTriggered: {
            const now = Date.now();
            for (const id of Object.keys(root.callbacks))
                if (root.callbacks[id].deadline <= now)
                    root.settle(id, null, root.serviceName + " request timed out. Try again.");
        }
    }
    Process {
        id: worker
        command: ["python3", "-u", Paths.file(root.backend)]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                if (!String(data).trim()) return;
                let response;
                try {
                    response = JSON.parse(data);
                    if (!response || response.id === undefined) throw new Error("missing response id");
                } catch (exception) {
                    const message = root.serviceName + " returned an unreadable response. Retry the request.";
                    root.failPending(message);
                    root.failed(message);
                    return;
                }
                root.settle(response.id, response.result, response.error);
            }
        }
        onExited: {
            root.stopped = true;
            root.failPending(root.serviceName + " service stopped. Close and reopen this module.");
        }
    }
    Component.onDestruction: worker.running = false
}
