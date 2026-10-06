import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core/theme"
import "../../widgets" as W
import "../../widgets/Catalogue.js" as Catalogue

Item {
    id: root
    property var controller
    property string kind: "songs"
    property string title: "Results"
    readonly property var visibleItems: controller ? controller.itemsFor(kind) : []

    ListModel { id: resultModel }
    onVisibleItemsChanged: Catalogue.update(resultModel, [], visibleItems, false,
                                            item => controller.recordKey(item))

    Rectangle {
        anchors.fill: parent
        radius: Theme.controlRadius
        color: Theme.surface
        border.color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 4
            W.Label {
                Layout.fillWidth: !paneSearch.visible
                Layout.preferredWidth: 50
                Layout.minimumWidth: 30
                text: root.title
                font.family: Theme.font; font.pixelSize: Theme.sp(14)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            MusicSearchInput {
                id: paneSearch
                visible: root.controller
                    && (root.controller.section === "discover" || root.controller.section === "favorites")
                Layout.fillWidth: visible
                Layout.minimumWidth: visible ? 40 : 0
                Layout.preferredHeight: 36
                fieldHeight: 36
                placeholderText: "Search " + (root.controller && root.controller.section === "favorites"
                    && root.controller.paneShowsFavorites(root.kind) ? "favorite " : "") + root.kind + "…"
                text: {
                    if (!root.controller) return "";
                    return root.controller.section === "favorites"
                        ? root.controller.favoriteQueries[root.kind] || ""
                        : root.controller.columnQueries[root.kind] || "";
                }
                onUserTextEdited: value => {
                    if (root.controller.section === "favorites") {
                        root.controller.changeFavoriteQuery(root.kind, value);
                        columnSearchDelay.stop();
                    } else {
                        root.controller.changeColumnQuery(root.kind, value);
                        if (value.trim()) columnSearchDelay.restart();
                        else columnSearchDelay.stop();
                    }
                }
                onDownPressed: results.forceActiveFocus()
            }
            W.IconButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: root.kind === "artists" && !!root.controller.selectedArtist
                text: "Clear artist selection"
                iconName: "brush-cleaning"
                iconSize: 16
                onClicked: root.controller.clearArtist()
            }
            W.IconButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: root.kind === "albums" && !!root.controller.selectedAlbum
                text: "Clear album selection"
                iconName: "brush-cleaning"
                iconSize: 16
                onClicked: root.controller.clearAlbum()
            }
            W.IconButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: root.kind === "songs" && !!root.controller.selectedSong
                text: "Clear song selection"
                iconName: "brush-cleaning"
                iconSize: 16
                onClicked: root.controller.clearSong()
            }
        }

        W.Label {
            visible: root.controller && root.controller.section === "discover"
                && !!root.controller.columnErrors[root.kind]
            Layout.fillWidth: true
            text: root.controller ? root.controller.columnErrors[root.kind] || "" : ""
            color: Theme.danger
            font.family: Theme.font; font.pixelSize: Theme.sp(11)
            wrapMode: Text.Wrap
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: results
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                objectName: "musicResultList"
                model: resultModel
                keyNavigationEnabled: true
                activeFocusOnTab: true
                function choose() {
                    if (!currentItem) return;
                    const item = currentItem.modelData;
                    if (root.kind === "songs") root.controller.selectSong(item, root.controller.itemsFor("songs"));
                    else if (root.kind === "artists") root.controller.selectArtist(item);
                    else root.controller.selectAlbum(item);
                }
                Keys.onReturnPressed: choose()
                Keys.onEnterPressed: choose()
                Keys.onSpacePressed: {
                    if (root.kind === "songs" && currentItem) root.controller.playSongs(root.controller.itemsFor("songs"), currentIndex);
                    else choose();
                }
                W.WheelScroll { view: results }
                ScrollBar.vertical: ScrollBar {}
                onContentYChanged: {
                    if (contentHeight > height && contentY >= contentHeight - height - 80)
                        root.controller.loadMore(root.kind);
                }

                delegate: Item {
                    id: resultRow
                    required property string payload
                    required property int index
                    readonly property var modelData: JSON.parse(payload)
                    width: results.width
                    height: 56
                    readonly property bool hasCover: !!modelData.cover
                    readonly property bool isSong: root.kind === "songs"
                    readonly property bool playing: isSong && root.controller.currentTrackKey === root.controller.recordKey(modelData)
                    readonly property bool selected: root.controller.isSelected(root.kind, modelData)

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.controlRadius
                        color: resultRow.selected ? Theme.accentSurface : rowMouse.containsMouse ? Theme.raised : "transparent"
                        border.color: results.activeFocus && results.currentIndex === resultRow.index || resultRow.selected ? Theme.accent : "transparent"
                        border.width: results.activeFocus && results.currentIndex === resultRow.index || resultRow.selected ? 1 : 0
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            results.currentIndex = resultRow.index;
                            results.forceActiveFocus();
                            if (resultRow.isSong) root.controller.selectSong(
                                resultRow.modelData, root.controller.itemsFor("songs"));
                            else if (root.kind === "artists") root.controller.selectArtist(resultRow.modelData);
                            else root.controller.selectAlbum(resultRow.modelData);
                        }
                        onDoubleClicked: {
                            if (resultRow.isSong)
                                root.controller.playSongs(root.controller.itemsFor("songs"), resultRow.index);
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 4
                        spacing: 7
                        visible: resultRow.isSong
                        W.Label {
                            Layout.preferredWidth: 22
                            text: String(resultRow.index + 1)
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.sp(11)
                            horizontalAlignment: Text.AlignRight
                        }
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 3
                            color: Theme.raised
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: resultRow.modelData.albumCover || resultRow.modelData.cover || ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96
                                sourceSize.height: 96
                                asynchronous: true
                                cache: true
                            }
                            W.Icon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                name: "music"
                                visible: !(resultRow.modelData.albumCover || resultRow.modelData.cover)
                                opacity: 0.6
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                W.Label {
                                    Layout.fillWidth: true
                                    text: resultRow.modelData.title || "Unknown Title"
                                    color: resultRow.playing ? Theme.accent : Theme.text
                                    font.family: Theme.font; font.pixelSize: Theme.sp(12)
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                MusicRowActionGroup {
                                    id: songActions
                                    entityHovered: rowMouse.containsMouse
                                    W.IconButton {
                                        objectName: "musicPaneTrackDownload"
                                        visible: !!root.controller.downloadCapabilities.track
                                        enabled: true
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        iconName: "download"
                                        iconSize: 16
                                        opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: "Download track"
                                        onClicked: root.controller.download("track", resultRow.modelData)
                                    }
                                    W.IconButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        iconName: "file-search-corner"
                                        iconSize: 16
                                        opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: "Find " + (resultRow.modelData.title || "this song")
                                        onClicked: root.controller.findLocal(resultRow.modelData, "song")
                                    }
                                    W.IconButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        iconName: "file-text"
                                        iconSize: 15
                                        opacity: songActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: "Show lyrics for " + (resultRow.modelData.title || "this song")
                                        onClicked: root.controller.showLyrics(resultRow.modelData)
                                    }
                                    W.IconButton {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        iconName: root.controller.isFavorite(resultRow.modelData) ? "star-filled" : "star"
                                        iconSize: 17
                                        opacity: root.controller.isFavorite(resultRow.modelData) || songActions.revealed || hovered || activeFocus || resultRow.playing ? 1 : 0
                                        text: (root.controller.isFavorite(resultRow.modelData) ? "Remove " : "Add ") + resultRow.modelData.title + " " + (root.controller.isFavorite(resultRow.modelData) ? "from" : "to") + " favorites"
                                        onClicked: root.controller.toggleFavorite(resultRow.modelData)
                                    }
                                }
                            }
                            W.Label {
                                Layout.fillWidth: true
                                text: (resultRow.modelData.artist || "Unknown Artist")
                                    + " · " + (resultRow.modelData.album || "Unknown Album")
                                color: Theme.muted
                                font.family: Theme.font; font.pixelSize: Theme.sp(10)
                                elide: Text.ElideRight
                            }
                        }
                        W.Label {
                            Layout.preferredWidth: 38
                            text: root.controller.formatTime(resultRow.modelData.duration)
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.sp(10)
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 4
                        spacing: 7
                        visible: !resultRow.isSong
                        Rectangle {
                            Layout.preferredWidth: root.kind === "artists" && !resultRow.hasCover ? 0 : 36
                            Layout.preferredHeight: 36
                            radius: root.kind === "artists" ? width / 2 : 3
                            color: root.kind === "artists" && !resultRow.hasCover
                                ? "transparent" : Theme.raised
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: resultRow.hasCover ? resultRow.modelData.cover : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96
                                sourceSize.height: 96
                                asynchronous: true
                                cache: true
                            }
                            W.Icon {
                                anchors.centerIn: parent
                                width: 17
                                height: 17
                                name: "music"
                                visible: root.kind !== "artists" && !resultRow.hasCover
                                opacity: 0.6
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                W.Label {
                                    Layout.fillWidth: true
                                    text: root.kind === "artists"
                                        ? resultRow.modelData.name || "Unknown Artist"
                                        : resultRow.modelData.title || "Unknown Album"
                                    color: resultRow.selected ? Theme.accent : Theme.text
                                    font.family: Theme.font; font.pixelSize: Theme.sp(12)
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                MusicRowActionGroup {
                                    id: artistActions
                                    visible: root.kind === "artists"
                                    W.IconButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        iconName: "file-search-corner"
                                        iconSize: 16
                                        opacity: artistActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: "Find " + (resultRow.modelData.name || "this artist")
                                        onClicked: root.controller.findLocal(resultRow.modelData, "artist")
                                    }
                                    entityHovered: rowMouse.containsMouse
                                    W.IconButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        iconName: "info"
                                        iconSize: 16
                                        opacity: artistActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: "Artist information for " + (resultRow.modelData.name || "this artist")
                                        onClicked: root.controller.showArtistInfo(resultRow.modelData)
                                    }
                                    W.IconButton {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        iconName: root.controller.isFavorite(resultRow.modelData) ? "star-filled" : "star"
                                        iconSize: 17
                                        opacity: root.controller.isFavorite(resultRow.modelData) || artistActions.revealed || hovered || activeFocus ? 1 : 0
                                        text: (root.controller.isFavorite(resultRow.modelData) ? "Remove " : "Add ") + (resultRow.modelData.name || "this artist") + " " + (root.controller.isFavorite(resultRow.modelData) ? "from" : "to") + " favorites"
                                        onClicked: root.controller.toggleFavorite(resultRow.modelData)
                                    }
                                }
                            }
                            W.Label {
                                visible: root.kind === "albums"
                                Layout.fillWidth: true
                                text: resultRow.modelData.artist || "Unknown Artist"
                                color: Theme.muted
                                font.family: Theme.font; font.pixelSize: Theme.sp(10)
                                elide: Text.ElideRight
                            }
                        }
                        MusicRowActionGroup {
                            id: albumActions
                            visible: root.kind === "albums"
                            entityHovered: rowMouse.containsMouse
                            W.IconButton {
                                objectName: "musicPaneAlbumDownload"
                                visible: !!root.controller.downloadCapabilities.album
                                enabled: true
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "download"
                                iconSize: 16
                                opacity: albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Download album"
                                onClicked: root.controller.download("album", resultRow.modelData)
                            }
                            W.IconButton {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                iconName: "file-search-corner"
                                iconSize: 16
                                opacity: albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: "Find " + (resultRow.modelData.title || "this album")
                                onClicked: root.controller.findLocal(resultRow.modelData, "album")
                            }
                            W.IconButton {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: root.controller.isFavorite(resultRow.modelData) ? "star-filled" : "star"
                                iconSize: 17
                                opacity: root.controller.isFavorite(resultRow.modelData) || albumActions.revealed || hovered || activeFocus ? 1 : 0
                                text: (root.controller.isFavorite(resultRow.modelData) ? "Remove " : "Add ") + (resultRow.modelData.name || resultRow.modelData.title || "item") + " " + (root.controller.isFavorite(resultRow.modelData) ? "from" : "to") + " favorites"
                                onClicked: root.controller.toggleFavorite(resultRow.modelData)
                            }
                        }
                    }
                }

                footer: Item {
                    width: results.width
                    height: (root.controller.hasMoreFor(root.kind) || root.controller.loadingMoreFor(root.kind)) ? 42 : 0
                    RowLayout {
                        anchors.centerIn: parent
                        W.Action {
                            visible: root.controller.hasMoreFor(root.kind) || root.controller.loadingMoreFor(root.kind)
                            enabled: !root.controller.loadingMoreFor(root.kind)
                            text: root.controller.loadingMoreFor(root.kind) ? "Loading…" : "Load more"
                            onClicked: root.controller.loadMore(root.kind)
                        }
                    }
                }
            }

            W.Label {
                anchors.centerIn: parent
                width: Math.max(80, parent.width - 24)
                visible: results.count === 0
                text: root.controller ? root.controller.emptyText(root.kind) : ""
                color: Theme.muted
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }

    Timer {
        id: columnSearchDelay
        interval: 350
        onTriggered: root.controller.requestColumnSearch(root.kind)
    }
}
