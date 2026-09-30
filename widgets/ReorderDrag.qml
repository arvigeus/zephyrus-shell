import QtQuick

// Local pointer gesture only; no Wayland/application drag-and-drop session.
DragHandler {
    id: root
    target: null
    acceptedButtons: Qt.LeftButton
    yAxis.enabled: false
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    cursorShape: Qt.ClosedHandCursor
    property bool dragging: false
    signal dragStarted(point position)
    signal dragMoved(point position)
    signal dragFinished(bool commit)
    onActiveChanged: if (active) {
        dragging = true;
        dragStarted(centroid.scenePosition);
    }
    onEnabledChanged: if (!enabled && dragging) {
        dragging = false;
        dragFinished(false);
    }
    Component.onDestruction: if (dragging) dragFinished(false)
    onCentroidChanged: if (active) dragMoved(centroid.scenePosition)
    onGrabChanged: (transition, point) => {
        if (transition === PointerDevice.UngrabExclusive && dragging) {
            dragging = false;
            // The centroid has already reset on release. The released event
            // point still carries the drop position, including outside drops.
            dragMoved(point.scenePosition);
            dragFinished(true);
        } else if (transition === PointerDevice.CancelGrabExclusive && dragging) {
            dragging = false;
            dragFinished(false);
        }
    }
}
