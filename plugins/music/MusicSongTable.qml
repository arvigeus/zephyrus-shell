import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core/theme"
import "../../widgets" as W
import "../../widgets/Catalogue.js" as Catalogue

ColumnLayout {
    id: root
    property var controller
    readonly property var visibleItems: controller ? controller.itemsFor("songs") : []
    spacing: 6

    ListModel { id: songModel }
    onVisibleItemsChanged: Catalogue.update(songModel, [], visibleItems, false,
                                            item => controller.recordKey(item))

    function focusList() {
        rows.forceActiveFocus();
        if (rows.count) rows.currentIndex = 0;
    }

    W.Label {
        visible: root.controller && root.controller.allSearchActive && !root.controller.searchQuery.trim()
        Layout.fillWidth: true
        Layout.preferredHeight: 20
        text: root.controller && root.controller.selectedGenreName
            ? "Most played in " + root.controller.selectedGenreName
            : "Most played"
        color: Theme.muted
        font.family: Theme.font; font.pixelSize: Theme.sp(13)
        font.weight: Font.DemiBold
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 10
        W.Label { Layout.fillWidth: true; Layout.preferredWidth: Math.max(240, rows.width * 0.38); text: "SONG"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(10); font.weight: Font.DemiBold }
        W.Label { Layout.fillWidth: true; Layout.preferredWidth: Math.max(160, rows.width * 0.25); text: "ARTIST"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(10); font.weight: Font.DemiBold }
        W.Label { Layout.fillWidth: true; Layout.preferredWidth: Math.max(160, rows.width * 0.25); text: "ALBUM"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(10); font.weight: Font.DemiBold }
        W.Label { Layout.preferredWidth: 54; horizontalAlignment: Text.AlignRight; text: "TIME"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(10); font.weight: Font.DemiBold }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: rows
            anchors.fill: parent
            clip: true
            objectName: "musicSongList"
            model: songModel
            keyNavigationEnabled: true
            activeFocusOnTab: true
            Keys.onReturnPressed: if (currentItem) root.controller.selectSong(currentItem.modelData, root.controller.itemsFor("songs"))
            Keys.onEnterPressed: if (currentItem) root.controller.selectSong(currentItem.modelData, root.controller.itemsFor("songs"))
            Keys.onSpacePressed: if (currentItem) root.controller.playSongs(root.controller.itemsFor("songs"), currentIndex)
            boundsBehavior: Flickable.StopAtBounds
            W.WheelScroll { view: rows }
            ScrollBar.vertical: ScrollBar {}
            onContentYChanged: {
                if (contentHeight > height && contentY >= contentHeight - height - 80)
                    root.controller.loadMore("songs");
            }

            delegate: Item {
                id: songRow
                required property string payload
                required property int index
                readonly property var modelData: JSON.parse(payload)
                width: rows.width
                height: 50
                readonly property bool playing: root.controller.currentTrackKey === root.controller.recordKey(modelData)
                readonly property bool selected: !!root.controller.selectedSong
                    && root.controller.recordKey(root.controller.selectedSong) === root.controller.recordKey(modelData)
                readonly property var artistFavorite: root.controller.artistsForSong(modelData)[0] || null
                readonly property var albumFavorite: root.controller.albumForSong(modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.controlRadius
                    color: songRow.playing || songRow.selected ? Theme.accentSurface : rowMouse.containsMouse ? Theme.surface : "transparent"
                    border.color: rows.activeFocus && rows.currentIndex === songRow.index || songRow.playing || songRow.selected ? Theme.accent : "transparent"
                    border.width: rows.activeFocus && rows.currentIndex === songRow.index || songRow.playing || songRow.selected ? 1 : 0
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        rows.currentIndex = songRow.index;
                        rows.forceActiveFocus();
                        root.controller.selectSong(songRow.modelData, root.controller.itemsFor("songs"));
                    }
                    onDoubleClicked: root.controller.playSongs(root.controller.itemsFor("songs"), songRow.index)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 6
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(240, rows.width * 0.38)
                        spacing: 7
                        HoverHandler { id: songColumnHover }
                        W.Label {
                            Layout.preferredWidth: 25
                            text: String(songRow.index + 1)
                            color: Theme.muted
                            horizontalAlignment: Text.AlignRight
                            font.family: Theme.font; font.pixelSize: Theme.sp(12)
                        }
                        W.Label {
                            Layout.fillWidth: true
                            text: songRow.modelData.title || "Unknown Title"
                            color: songRow.playing ? Theme.accent : Theme.text
                            font.family: Theme.font; font.pixelSize: Theme.sp(13)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        MusicRowActionGroup {
                            id: songActions
                            entityHovered: songColumnHover.hovered
                            W.IconButton {
                                objectName: "musicTableTrackDownload"
                                visible: !!root.controller.downloadCapabilities.track
                                enabled: !root.controller.downloadLoading
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "download"
                                iconSize: 16
                                opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Download track"
                                onClicked: root.controller.download("track", songRow.modelData)
                            }
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "file-search-corner"
                                iconSize: 16
                                opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Find " + (songRow.modelData.title || "this song")
                                onClicked: root.controller.findLocal(songRow.modelData, "song")
                            }
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "file-text"
                                iconSize: 15
                                opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Show lyrics for " + (songRow.modelData.title || "this song")
                                onClicked: root.controller.showLyrics(songRow.modelData)
                            }
                            W.IconButton {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: root.controller.isFavorite(songRow.modelData) ? "star-filled" : "star"
                                iconSize: 18
                                opacity: root.controller.isFavorite(songRow.modelData) || songActions.revealed || hovered || activeFocus ? 1 : 0
                                text: (root.controller.isFavorite(songRow.modelData) ? "Remove " : "Add ") + songRow.modelData.title + " " + (root.controller.isFavorite(songRow.modelData) ? "from" : "to") + " favorites"
                                onClicked: root.controller.toggleFavorite(songRow.modelData)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(160, rows.width * 0.25)
                        spacing: 4
                        HoverHandler { id: artistColumnHover }
                        W.Label {
                            Layout.fillWidth: true
                            text: songRow.modelData.artist || "Unknown Artist"
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.sp(12)
                            elide: Text.ElideRight
                        }
                        MusicRowActionGroup {
                            id: artistActions
                            entityHovered: artistColumnHover.hovered
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "file-search-corner"
                                iconSize: 16
                                opacity: artistActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Find " + (songRow.modelData.artist || "this artist")
                                onClicked: root.controller.findLocal(songRow.artistFavorite, "artist")
                            }
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "info"
                                iconSize: 16
                                opacity: artistActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Artist information for " + (songRow.modelData.artist || "Unknown Artist")
                                onClicked: root.controller.showArtistInfo(songRow.artistFavorite)
                            }
                            W.IconButton {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: root.controller.isFavorite(songRow.artistFavorite) ? "star-filled" : "star"
                                iconSize: 17
                                opacity: root.controller.isFavorite(songRow.artistFavorite) || artistActions.revealed || hovered || activeFocus ? 1 : 0
                                text: (root.controller.isFavorite(songRow.artistFavorite) ? "Remove " : "Add ")
                                    + (songRow.modelData.artist || "Unknown Artist") + " "
                                    + (root.controller.isFavorite(songRow.artistFavorite) ? "from" : "to") + " favorites"
                                onClicked: root.controller.toggleFavorite(songRow.artistFavorite)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(160, rows.width * 0.25)
                        spacing: 6
                        HoverHandler { id: albumColumnHover }
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 3
                            color: Theme.raised
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: songRow.modelData.albumCover || songRow.modelData.cover || ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96
                                sourceSize.height: 96
                                asynchronous: true
                                cache: true
                            }
                            W.Icon {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                name: "music"
                                visible: !(songRow.modelData.albumCover || songRow.modelData.cover)
                                opacity: 0.6
                            }
                        }
                        W.Label {
                            Layout.fillWidth: true
                            text: songRow.modelData.album || "Unknown Album"
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.sp(12)
                            elide: Text.ElideRight
                        }
                        MusicRowActionGroup {
                            id: albumActions
                            entityHovered: albumColumnHover.hovered
                            W.IconButton {
                                objectName: "musicTableAlbumDownload"
                                visible: !!root.controller.downloadCapabilities.album
                                enabled: !root.controller.downloadLoading
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "download"
                                iconSize: 16
                                opacity: albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Download album"
                                onClicked: root.controller.download("album", songRow.albumFavorite)
                            }
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "file-search-corner"
                                iconSize: 16
                                opacity: albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Find " + (songRow.modelData.album || "this album")
                                onClicked: root.controller.findLocal(songRow.albumFavorite, "album")
                            }
                            W.IconButton {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: root.controller.isFavorite(songRow.albumFavorite) ? "star-filled" : "star"
                                iconSize: 17
                                opacity: root.controller.isFavorite(songRow.albumFavorite) || albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: (root.controller.isFavorite(songRow.albumFavorite) ? "Remove " : "Add ")
                                    + (songRow.modelData.album || "Unknown Album") + " "
                                    + (root.controller.isFavorite(songRow.albumFavorite) ? "from" : "to") + " favorites"
                                onClicked: root.controller.toggleFavorite(songRow.albumFavorite)
                            }
                        }
                    }
                    W.Label {
                        Layout.preferredWidth: 54
                        text: root.controller.formatTime(songRow.modelData.duration)
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.sp(12)
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            footer: Item {
                width: rows.width
                height: (root.controller.hasMoreFor("songs") || !!(root.controller.paging.songs || {}).loading) ? 42 : 0
                RowLayout {
                    anchors.centerIn: parent
                    W.BusySpinner {
                        visible: !!(root.controller.paging.songs || {}).loading
                        running: visible
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }
                    W.Action {
                        visible: root.controller.hasMoreFor("songs")
                        text: "Load more songs"
                        onClicked: root.controller.loadMore("songs")
                    }
                }
            }
        }

        W.Label {
            anchors.centerIn: parent
            width: Math.max(100, parent.width - 32)
            visible: rows.count === 0
            text: root.controller ? root.controller.emptyText("songs") : ""
            color: Theme.muted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
