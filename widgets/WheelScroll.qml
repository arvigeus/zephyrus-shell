import QtQuick

WheelHandler {
    id: root
    required property Flickable view
    property bool horizontal: false
    property real pixelsPerNotch: 320
    property real pixelMultiplier: 1.5
    property real pendingPosition: 0
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null
    // Pixel deltas are already in screen pixels. Only angle deltas represent notches.
    function scroll(pixelDelta, angleDelta) {
        const pixel = horizontal ? (pixelDelta.x || pixelDelta.y) : pixelDelta.y;
        const angle = horizontal ? (angleDelta.x || angleDelta.y) : angleDelta.y;
        const delta = pixel ? pixel * pixelMultiplier : angle / 120 * pixelsPerNotch;
        if (!delta) return;
        const origin = horizontal ? view.originX : view.originY;
        const extent = horizontal ? view.contentWidth - view.width : view.contentHeight - view.height;
        const position = horizontal ? view.contentX : view.contentY;
        const start = motion.running ? pendingPosition : position;
        motion.stop(); view.cancelFlick();
        pendingPosition = Math.max(origin, Math.min(origin + Math.max(0, extent), start - delta));
        if (pixel) {
            if (horizontal) view.contentX = pendingPosition;
            else view.contentY = pendingPosition;
        } else {
            motion.to = pendingPosition;
            motion.start();
        }
    }
    onWheel: event => {
        scroll(event.pixelDelta, event.angleDelta);
        event.accepted = true;
    }
    property NumberAnimation motion: NumberAnimation {
        target: root.view; property: root.horizontal ? "contentX" : "contentY"
        duration: 90; easing.type: Easing.OutCubic
    }
}
