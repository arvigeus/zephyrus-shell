import QtQuick

Item {
    id: root
    property url source
    property int fillMode: Image.PreserveAspectCrop
    property int horizontalAlignment: Image.AlignHCenter
    property int imageWidth: 2560
    property int duration: 320
    property bool fadeInOnTop: false
    property bool resetOnSourceChange: false
    property bool frontIsA: false
    property url displayedSource: ""
    readonly property real imageOpacity: Math.max(a.opacity,b.opacity)
    readonly property bool loading: a.status === Image.Loading || b.status === Image.Loading
    readonly property bool transitioning: fade.running
    property string failedSource: ""
    property int retryCount: 0
    readonly property bool hasImage: !!displayedSource.toString()
    property var incoming: null
    function clear() {
        fade.stop();
        retry.stop();
        incoming = null;
        a.opacity = 0; b.opacity = 0;
        a.source = ""; b.source = "";
        frontIsA = false;
        displayedSource = "";
        failedSource = "";
        retryCount = 0;
    }
    onSourceChanged: {
        failedSource = "";
        retryCount = 0;
        retry.stop();
        if (resetOnSourceChange) {
            clear();
        } else if (fade.running && incoming && incoming.source.toString() !== source.toString()) {
            // A newer request supersedes the image currently fading in.
            fade.stop();
            const outgoing = frontIsA ? a : b;
            outgoing.opacity = 1;
            incoming.opacity = 0;
            incoming.source = "";
            incoming = null;
        }
        prepare();
    }
    function prepare() {
        if (fade.running || source.toString() === displayedSource.toString() || (failedSource && failedSource === source.toString())) return;
        incoming = frontIsA ? b : a;
        incoming.opacity = 0;
        incoming.cache = retryCount === 0;
        incoming.source = source;
        if (!source.toString()) { fade.start(); return; }
        if (incoming && incoming.status === Image.Ready) ready(incoming);
    }
    function ready(item) {
        if (item !== incoming || fade.running) return;
        if (item.status === Image.Error) {
            failedSource = item.source.toString();
            item.source = "";
            if (retryCount < 1 && source.toString()) { retryCount++; retry.restart(); }
            if (displayedSource.toString()) { incoming = null; return; }
            fade.start();
            return;
        }
        if (item.status !== Image.Ready) return;
        if (item.source.toString() !== source.toString()) { prepare(); return; }
        if (!displayedSource.toString()) {
            item.opacity = 1;
            frontIsA = item === a;
            incoming = null;
            // Observers may request the next resolution as soon as this one is
            // displayed. Publish it only after the buffer state is consistent.
            displayedSource = item.source;
        } else fade.start();
    }
    Timer {
        id: retry
        interval: 1800
        onTriggered: {
            if (!root.source.toString() || root.source.toString() !== root.failedSource) return;
            root.failedSource = "";
            root.prepare();
        }
    }
    Image { id: a; objectName: "imageA"; anchors.fill: parent; asynchronous: true; opacity: 0; fillMode: root.fillMode; horizontalAlignment: root.horizontalAlignment; sourceSize.width: root.imageWidth; onStatusChanged: root.ready(a) }
    Image { id: b; objectName: "imageB"; anchors.fill: parent; asynchronous: true; opacity: 0; fillMode: root.fillMode; horizontalAlignment: root.horizontalAlignment; sourceSize.width: root.imageWidth; onStatusChanged: root.ready(b) }
    ParallelAnimation {
        id: fade
        NumberAnimation { target: root.incoming; property: "opacity"; to: root.incoming && root.incoming.source.toString() ? 1 : 0; duration: root.duration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.frontIsA ? a : b; property: "opacity"; to: root.fadeInOnTop ? 1 : 0; duration: root.duration; easing.type: Easing.InOutQuad }
        onFinished: {
            const completed = root.incoming;
            const outgoing = root.frontIsA ? a : b;
            root.frontIsA = completed === a;
            outgoing.opacity = 0;
            outgoing.source = "";
            root.incoming = null;
            root.displayedSource = completed.source;
            root.prepare();
        }
    }
}
