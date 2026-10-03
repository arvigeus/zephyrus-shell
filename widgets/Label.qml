import QtQuick
import "../core/theme"

Text {
    color: Theme.text
    font.family: Theme.font
    font.pixelSize: Theme.sp(14)
    textFormat: Text.PlainText
    elide: Text.ElideRight
}
