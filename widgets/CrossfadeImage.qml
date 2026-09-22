import QtQuick

Item {
    id: root
    property url source
    property int fillMode: Image.PreserveAspectCrop
    property int horizontalAlignment: Image.AlignHCenter
    property int imageWidth: 2560
    property int duration: 320
    property bool frontIsA: false
    property url displayedSource: ""
    readonly property real imageOpacity: Math.max(a.opacity,b.opacity)
    readonly property bool loading: a.status === Image.Loading || b.status === Image.Loading
    readonly property bool transitioning: fade.running
    property string failedSource: ""
    readonly property bool hasImage: !!displayedSource.toString()
    property var incoming: null
    onSourceChanged: { failedSource = ""; prepare(); }
    function prepare() {
        if (fade.running || source.toString() === displayedSource.toString() || (failedSource && failedSource === source.toString())) return;
        incoming = frontIsA ? b : a;
        incoming.opacity = 0;
        incoming.source = source;
        if (!source.toString()) { fade.start(); return; }
        if (incoming && incoming.status === Image.Ready) ready(incoming);
    }
    function ready(item) {
        if (item !== incoming || fade.running) return;
        if (item.status === Image.Error) {
            failedSource = item.source.toString();
            item.source = "";
            fade.start();
            return;
        }
        if (item.status !== Image.Ready) return;
        if (item.source.toString() !== source.toString()) { prepare(); return; }
        if (!hasImage) {
            item.opacity = 1;
            displayedSource = item.source;
            frontIsA = item === a;
            incoming = null;
        } else fade.start();
    }
    Image { id: a; objectName: "imageA"; anchors.fill: parent; asynchronous: true; opacity: 0; fillMode: root.fillMode; horizontalAlignment: root.horizontalAlignment; sourceSize.width: root.imageWidth; onStatusChanged: root.ready(a) }
    Image { id: b; objectName: "imageB"; anchors.fill: parent; asynchronous: true; opacity: 0; fillMode: root.fillMode; horizontalAlignment: root.horizontalAlignment; sourceSize.width: root.imageWidth; onStatusChanged: root.ready(b) }
    ParallelAnimation {
        id: fade
        NumberAnimation { target: root.incoming; property: "opacity"; to: root.incoming && root.incoming.source.toString() ? 1 : 0; duration: root.duration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.frontIsA ? a : b; property: "opacity"; to: 0; duration: root.duration; easing.type: Easing.InOutQuad }
        onFinished: {
            root.displayedSource = root.incoming.source;
            const outgoing = root.frontIsA ? a : b;
            root.frontIsA = root.incoming === a;
            outgoing.source = "";
            root.incoming = null;
            root.prepare();
        }
    }
}
