import QtQuick

WheelHandler {
    required property Flickable view
    property real pixelsPerNotch: 108
    property real pixelMultiplier: 1
    target: null
    onWheel: event => {
        const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y * pixelMultiplier : event.angleDelta.y / 120 * pixelsPerNotch;
        view.cancelFlick();
        view.contentY = Math.max(view.originY, Math.min(view.originY + Math.max(0, view.contentHeight - view.height), view.contentY - delta));
        event.accepted = true;
    }
}
