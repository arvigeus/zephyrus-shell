import QtQuick
import "../core/theme"
Image {
    id: root
    property string name: "settings"
    property color color: Theme.text
    function themedSvg(markup) {
        return markup.replace(/#(?:f1f2f6|ffffff)/gi, root.color.toString())
            .replace(/#ff465c/gi, Theme.accent.toString())
            .replace(/#ff8090/gi, Theme.danger.toString());
    }
    source: !name ? "" : Theme.icons[name]
        ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(themedSvg(Theme.icons[name]))
        : Qt.resolvedUrl("../assets/lucide/" + name + ".svg")
    sourceSize.width: 24; sourceSize.height: 24
    fillMode: Image.PreserveAspectFit
}
