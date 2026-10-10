import QtQuick
import QtQuick.Layouts
import "../../widgets" as W
import "../../core"

W.Action {
    id: root
    objectName: "episodeRow"
    property var episode: ({})
    property var localFile: ({})
    property bool findAvailable: true
    signal findRequested()
    signal subtitlesRequested()
    signal deleteRequested(string path)
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
            W.Label { visible: !!root.episode.date; Layout.fillWidth: true; text: root.episode.date || ""; color: Theme.muted }
        }
        W.IconButton { visible: root.findAvailable; iconName: "file-search-corner"; text: "Find episode " + root.episode.number; onClicked: root.findRequested() }
        W.IconButton { visible: !!root.localFile.path; iconName: "file-text"; text: "Subtitles for episode " + root.episode.number; onClicked: root.subtitlesRequested() }
        W.HoldDelete { visible: !!root.localFile.path; torrent: !!root.localFile.torrent; onActivated: root.deleteRequested(root.localFile.path) }
    }
}
