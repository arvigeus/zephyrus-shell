import QtQuick
import "../core"

Rectangle {
    color: "#0b0c10"
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            // Static diagonal machining lines, inspired by the Zephyrus lid.
            ctx.fillStyle = "#111319";
            ctx.beginPath(); ctx.moveTo(width * 0.55, 0); ctx.lineTo(width, 0);
            ctx.lineTo(width, height); ctx.lineTo(width * 0.13, height); ctx.closePath(); ctx.fill();
            ctx.lineWidth = 1;
            for (let i = 0; i < 18; i++) {
                ctx.strokeStyle = i === 8 ? "rgba(255,70,92,0.25)" : "rgba(161,166,181,0.045)";
                ctx.beginPath(); ctx.moveTo(width * 0.55 + i * 18, 0);
                ctx.lineTo(width * 0.13 + i * 18, height); ctx.stroke();
            }
            ctx.fillStyle = "rgba(161,166,181,0.12)";
            for (let x = 40; x < width * 0.32; x += 14)
                for (let y = height * 0.64; y < height - 40; y += 14) {
                    if (x + (height - y) * 0.5 < width * 0.33) ctx.fillRect(x, y, 1, 1);
                }
        }
    }
}
