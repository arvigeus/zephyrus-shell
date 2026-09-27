import QtQuick
import "../core/theme"

Rectangle {
    property bool gridMode: false
    x: -Theme.moduleMargin
    y: -Theme.moduleTopMargin
    width: parent.width + Theme.moduleMargin * 2
    height: parent.height + Theme.moduleMargin + Theme.moduleTopMargin
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Theme.scrim(0.92) }
        GradientStop { position: 0.6; color: Theme.scrim(gridMode ? 0.86 : 0.6) }
        GradientStop { position: 1; color: Theme.scrim(gridMode ? 0.92 : 0.2) }
    }
}
