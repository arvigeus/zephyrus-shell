pragma Singleton
import QtQuick

QtObject {
    readonly property string root: decodeURIComponent(Qt.resolvedUrl("../").toString().replace(/^file:\/\//, ""))
    function file(relative) { return root.replace(/\/$/, "") + "/" + relative; }
}
