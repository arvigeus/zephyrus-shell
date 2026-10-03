import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../core"
import "../widgets"

Rectangle {
    id: root
    property url wallpaperSource: ""
    color: Theme.background
    FileView {
        id: setting
        readonly property string configuredRoot: Quickshell.env("XDG_CONFIG_HOME") || ""
        path: (configuredRoot.startsWith("/") ? configuredRoot : Quickshell.env("HOME") + "/.config")
            + "/zephyrus-shell/wallpaper.json"
        preload: true
        blockLoading: false
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.wallpaperSource = typeof data.image === "string" && data.image.startsWith("file:///") ? data.image : "";
            } catch (error) { root.wallpaperSource = ""; }
        }
        onLoadFailed: root.wallpaperSource = ""
    }
    Canvas {
        id: pattern
        anchors.fill: parent
        Connections {
            target: Theme
            function onBackgroundChanged() { pattern.requestPaint(); }
            function onSurfaceChanged() { pattern.requestPaint(); }
            function onAccentChanged() { pattern.requestPaint(); }
            function onMutedChanged() { pattern.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            // Static diagonal machining lines, inspired by the Zephyrus lid.
            ctx.fillStyle = Theme.surface;
            ctx.beginPath(); ctx.moveTo(width * 0.55, 0); ctx.lineTo(width, 0);
            ctx.lineTo(width, height); ctx.lineTo(width * 0.13, height); ctx.closePath(); ctx.fill();
            ctx.lineWidth = 1;
            for (let i = 0; i < 18; i++) {
                const ink = i === 8 ? Theme.accent : Theme.muted;
                ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, i === 8 ? 0.25 : 0.045);
                ctx.beginPath(); ctx.moveTo(width * 0.55 + i * 18, 0);
                ctx.lineTo(width * 0.13 + i * 18, height); ctx.stroke();
            }
            ctx.fillStyle = Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.12);
            for (let x = 40; x < width * 0.32; x += 14)
                for (let y = height * 0.64; y < height - 40; y += 14) {
                    if (x + (height - y) * 0.5 < width * 0.33) ctx.fillRect(x, y, 1, 1);
                }
        }
    }
    CrossfadeImage {
        objectName: "desktopWallpaperImage"
        anchors.fill: parent
        source: root.wallpaperSource
        imageWidth: Math.ceil(root.width * Screen.devicePixelRatio)
    }
}
