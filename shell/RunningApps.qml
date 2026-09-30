import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../core"

Item {
    id: root
    required property var window
    property real maximumWidth: 240
    // Reading values keeps lookup bindings current after the initial desktop scan.
    readonly property var applicationEntries: DesktopEntries.applications.values
    property var draggedWindow: null
    property var dropWindow: null
    property bool dropAfter: false
    property real dropPosition: 0
    property point dragPoint: Qt.point(0, 0)

    function beginDrag(window) {
        draggedWindow = window;
        dropWindow = null;
    }
    function updateDrop(scenePoint) {
        dragPoint = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        updateDropTarget();
    }
    function updateDropTarget() {
        dropWindow = null;
        if (!draggedWindow || dragPoint.x < 0 || dragPoint.x > width || dragPoint.y < 0 || dragPoint.y > height) return;
        const x = dragPoint.x + runningApps.contentX;
        let nearest = null;
        let distance = Infinity;
        for (let i = 0; i < windows.count; ++i) {
            const button = windows.itemAt(i);
            if (!button || button.modelData === draggedWindow) continue;
            const delta = Math.abs(x - button.x - button.width / 2);
            if (delta < distance) { nearest = button; distance = delta; }
        }
        if (!nearest || !WindowList.canDrop(draggedWindow, nearest.modelData)) return;
        dropWindow = nearest.modelData;
        dropAfter = x >= nearest.x + nearest.width / 2;
        dropPosition = nearest.x + (dropAfter ? nearest.width + row.spacing / 2 : -row.spacing / 2);
    }
    function finishDrag(commit) {
        const source = draggedWindow;
        const target = dropWindow;
        const after = dropAfter;
        draggedWindow = null;
        dropWindow = null;
        if (commit && source && target) WindowList.reorder(source, target, after);
    }
    Timer {
        interval: 40; repeat: true
        running: !!root.draggedWindow
        onTriggered: {
            if (root.dragPoint.x < 0 || root.dragPoint.x > root.width
                || root.dragPoint.y < 0 || root.dragPoint.y > root.height) return;
            const direction = root.dragPoint.x < 20 ? -1 : root.dragPoint.x > root.width - 20 ? 1 : 0;
            const limit = Math.max(0, runningApps.contentWidth - runningApps.width);
            runningApps.contentX = Math.max(0, Math.min(limit, runningApps.contentX + direction * 10));
            root.updateDropTarget();
        }
    }
    Rectangle {
        z: 1
        visible: !!root.draggedWindow && !!root.dropWindow
        x: Math.max(0, Math.min(root.width - width, root.dropPosition - runningApps.contentX))
        y: 4; width: 2; height: root.height - 8
        color: Theme.accent
    }
    width: Math.min(row.implicitWidth, maximumWidth)
    height: Theme.pillControlHeight
    visible: width > 0
    clip: true
    PillBackground { anchors.fill: parent; z: -1 }
    Flickable {
        id: runningApps
        WheelScroll { view: runningApps; horizontal: true }
        anchors.fill: parent; contentWidth: row.implicitWidth; contentHeight: root.height
        flickableDirection: Flickable.HorizontalFlick
        Row {
            id: row; spacing: 6
            Repeater {
                id: windows
                model: ScriptModel { values: WindowList.windows }
                BarAction {
                    id: windowButton
                    required property var modelData
                    width: Theme.pillControlHeight
                    text: modelData.title || modelData.appId
                    highlighted: modelData.activated
                    readonly property var desktopEntry: {
                        const entries = root.applicationEntries;
                        return DesktopEntries.heuristicLookup(modelData.appId);
                    }
                    contentItem: AppIcon {
                        icon: windowButton.desktopEntry ? windowButton.desktopEntry.icon : windowButton.modelData.appId
                    }
                    property bool dragged: false
                    opacity: root.draggedWindow === modelData ? 0.5 : 1
                    onPressed: dragged = false
                    onClicked: if (!dragged) modelData.activate()
                    ReorderDrag {
                        enabled: WindowList.canDrag(windowButton.modelData)
                        onDragStarted: position => {
                            windowButton.dragged = true;
                            root.beginDrag(windowButton.modelData);
                            root.updateDrop(position);
                        }
                        onDragMoved: position => root.updateDrop(position)
                        onDragFinished: commit => root.finishDrag(commit)
                    }
                }
            }
        }
    }
}
