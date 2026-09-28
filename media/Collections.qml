import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets" as W

W.ScrollArea {
    id: root
    property var sections: []
    property bool loading: false
    property bool loaded: false
    property string error: ""
    signal activated(var title)
    clip: true
    contentWidth: availableWidth

    ColumnLayout {
        width: parent.width
        spacing: 18
        BusyIndicator { visible: root.loading; running: visible; Layout.alignment: Qt.AlignHCenter }
        W.Label { visible: !!root.error; text: root.error; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
        W.Label {
            visible: root.loaded && !root.loading && !root.error && !root.sections.length
            text: "No collections or recommendations available."
            color: Theme.muted
        }
        Repeater {
            model: root.sections
            ColumnLayout {
                id: section
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                W.Label { text: modelData.label; font.pixelSize: 18; font.bold: true }
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: modelData.items
                        Poster {
                            objectName: section.modelData.label === "Recommended" ? "recommendedCollectionCard" : "relatedCollectionCard"
                            required property var modelData
                            width: 138; height: 252
                            title: modelData
                            subtitle: modelData.relation || String(modelData.year || "")
                            onClicked: root.activated(modelData)
                        }
                    }
                }
            }
        }
    }
}
