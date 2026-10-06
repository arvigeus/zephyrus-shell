import QtQuick
import Quickshell
import "../../services"

JobWorker {
    id: root
    objectName: "filesService"
    backend: "plugins/files/backend.py"
    serviceName: "Files"
    readonly property string homePath: Quickshell.env("HOME") || "/"
    property var editSessions: []
    property bool pollingEdits: false
    property bool pollEditsAgain: false
    property bool awaitingEditSnapshot: false
    signal externalFileOpened()
    readonly property int activeEditCount: (awaitingEditSnapshot ? 1 : 0) + editSessions.filter(session => session.active).length

    function pollEdits() {
        if (stopped) return;
        if (pollingEdits) { pollEditsAgain = true; return; }
        pollingEdits = true;
        request("edit_sessions", {}, (result, error) => {
            if (!error) {
                editSessions = result.sessions || [];
                if (!pollEditsAgain) awaitingEditSnapshot = false;
                if (activeEditCount) pollJobs();
            }
            pollingEdits = false;
            if (pollEditsAgain) { pollEditsAgain = false; pollEdits(); }
        });
    }
    function openCloudFile(provider, entry) {
        startJob("open", {provider: provider, path: entry.path, title: "Open " + entry.name});
    }
    function editSessionAction(id, pause) {
        awaitingEditSnapshot = true;
        request("edit_session_action", {session_id: id, pause: !!pause}, (result, error) => {
            if (error) jobStartFailed(error);
            pollEdits();
            if (!error && result && result.opened) externalFileOpened();
        });
    }
    onReady: pollEdits()
    Connections {
        target: root
        function onJobFinished(job) {
            root.awaitingEditSnapshot = true;
            root.pollEdits();
        }
        function onStoppedChanged() {
            if (root.stopped) {
                root.editSessions = [];
                root.awaitingEditSnapshot = false;
                root.pollingEdits = false;
                root.pollEditsAgain = false;
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: !root.stopped; onTriggered: root.pollEdits() }

    function connectDrive() {
        if (stopped) restart();
        startJob("connect_drive", {title: "Connect Google Drive"});
    }
}
