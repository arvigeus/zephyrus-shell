import QtQuick
import QtQuick.Layouts
import "../widgets" as W
import "../core"

W.Action {
    id: root
    objectName: "episodeRow"
    property var episode: ({})
    implicitHeight: Math.max(81, episodeText.implicitHeight) + 16
    text: (episode.number || "") + ". " + (episode.title || "")
    contentItem: RowLayout {
        spacing: 16
        W.CrossfadeImage { source: root.episode.image || ""; imageWidth: 300; Layout.preferredWidth: 144; Layout.preferredHeight: 81; Layout.alignment: Qt.AlignTop }
        ColumnLayout {
            id: episodeText
            Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
            spacing: 6
            W.Label { Layout.fillWidth: true; text: root.text; wrapMode: Text.Wrap; font.weight: Font.DemiBold }
            W.Label { Layout.fillWidth: true; text: root.episode.plot || ""; wrapMode: Text.Wrap; color: Theme.muted }
        }
    }
}
