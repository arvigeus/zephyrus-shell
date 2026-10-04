import QtQuick
import QtTest
import "../../plugins/music" as Music

TestCase {
    name: "MusicPagination"
    width: 1000; height: 660; visible: true
    when: windowShown

    Item {
        id: controller
        property var items: ({songs: [], albums: []})
        property string section: "discover"
        property bool allSearchActive: true
        property string searchQuery: "music"
        property string selectedGenreName: ""
        property var favoriteQueries: ({})
        property var columnQueries: ({})
        property var columnErrors: ({})
        property var paging: ({})
        property var downloadCapabilities: ({track: false, album: false})
        property bool downloadLoading: false
        property var selectedArtist: null
        property var selectedAlbum: null
        property var selectedSong: null
        property string currentTrackKey: ""
        function itemsFor(kind) { return items[kind] || []; }
        function recordKey(item) { return item.kind + "|" + item.id; }
        function hasMoreFor(kind) { return false; }
        function loadingMoreFor(kind) { return false; }
        function paneShowsFavorites(kind) { return false; }
        function isFavorite(item) { return false; }
        function isSelected(kind, item) { return false; }
        function emptyText(kind) { return ""; }
        function formatTime(seconds) { return "3:00"; }
        function artistsForSong(song) { return []; }
        function albumForSong(song) { return null; }
        function loadMore(kind) {}
        function download(kind, item) {}
    }

    Music.MusicResultPane {
        id: songsPane
        width: 300; height: 250
        controller: controller
        kind: "songs"
    }
    Music.MusicResultPane {
        id: albumsPane
        x: 320; width: 300; height: 250
        controller: controller
        kind: "albums"
    }
    Music.MusicSongTable {
        id: songTable
        y: 270; width: 750; height: 300
        controller: controller
    }

    function makeItems(kind, count) {
        const result = [];
        for (let i = 0; i < count; ++i)
            result.push({kind: kind, id: String(i), title: kind + " " + i,
                         artist: "Artist", album: "Album", duration: 180});
        return result;
    }

    function test_appending_pages_keeps_all_three_scroll_positions() {
        controller.items = {songs: makeItems("song", 30), albums: makeItems("album", 30)};
        const songList = findChild(songsPane, "musicResultList");
        const albumList = findChild(albumsPane, "musicResultList");
        const tableList = findChild(songTable, "musicSongList");
        verify(songList && albumList && tableList);
        tryCompare(songList, "count", 30);
        tryCompare(albumList, "count", 30);
        tryCompare(tableList, "count", 30);
        songList.contentY = 430;
        albumList.contentY = 460;
        tableList.contentY = 490;
        const positions = [songList.contentY, albumList.contentY, tableList.contentY];
        controller.items = {songs: makeItems("song", 55), albums: makeItems("album", 55)};
        tryCompare(songList, "count", 55);
        tryCompare(albumList, "count", 55);
        tryCompare(tableList, "count", 55);
        compare(songList.contentY, positions[0]);
        compare(albumList.contentY, positions[1]);
        compare(tableList.contentY, positions[2]);
    }

    function test_download_actions_follow_each_capability() {
        controller.items = {
            songs: makeItems("song", 1),
            albums: makeItems("album", 1)
        };
        tryCompare(findChild(songsPane, "musicResultList"), "count", 1);
        tryCompare(findChild(albumsPane, "musicResultList"), "count", 1);
        tryCompare(findChild(songTable, "musicSongList"), "count", 1);
        // The preceding pagination test leaves the views scrolled. Delegate
        // creation happens after model counts change and the next layout pass.
        for (const view of [findChild(songsPane, "musicResultList"),
                            findChild(albumsPane, "musicResultList"),
                            findChild(songTable, "musicSongList")])
            view.positionViewAtBeginning();
        tryVerify(() => findChild(songsPane, "musicPaneTrackDownload")
                     && findChild(albumsPane, "musicPaneAlbumDownload")
                     && findChild(songTable, "musicTableTrackDownload")
                     && findChild(songTable, "musicTableAlbumDownload"));
        const trackPane = findChild(songsPane, "musicPaneTrackDownload");
        const albumPane = findChild(albumsPane, "musicPaneAlbumDownload");
        const trackTable = findChild(songTable, "musicTableTrackDownload");
        const albumTable = findChild(songTable, "musicTableAlbumDownload");
        verify(trackPane && albumPane && trackTable && albumTable);
        const cases = [
            {track: false, album: false},
            {track: true, album: false},
            {track: false, album: true},
            {track: true, album: true}
        ];
        for (const capabilities of cases) {
            controller.downloadCapabilities = capabilities;
            compare(trackPane.visible, capabilities.track);
            compare(trackTable.visible, capabilities.track);
            compare(albumPane.visible, capabilities.album);
            compare(albumTable.visible, capabilities.album);
        }
        controller.downloadCapabilities = ({track: false, album: false});
    }
}
