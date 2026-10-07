import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "../../core"
import "../../widgets" as W
import "../../media" as M

ColumnLayout {
    id: root
    property var host
    property bool playbackWantsRetention: false
    function updateRetention() { if (host) host.requestKeepRunning("music", playbackWantsRetention || downloadLoading || torrentService.keepRunning); }
    function requestRetention(enabled) { playbackWantsRetention = enabled; updateRetention(); }
    property string section: "discover"
    property var localSongs: []
    property string localQuery: ""
    property bool localLoading: false
    property bool torrentOpen: false
    property var torrentTarget: ({})
    property bool torrentTracksLoading: false
    property int torrentGeneration: 0
    property bool filtersView: false
    property string searchQuery: ""
    property string selectedGenreId: ""
    property string selectedGenreName: ""
    property string genreQuery: ""
    property var results: ({artists: [], albums: [], songs: []})
    property var paging: ({})
    property var columnQueries: ({songs: "", artists: "", albums: ""})
    property var columnResults: ({songs: [], artists: [], albums: []})
    property var paneResults: ({songs: [], artists: [], albums: []})
    property var paneOverrides: ({songs: false, artists: false, albums: false})
    property var columnPaging: ({})
    property var columnGenerations: ({songs: 0, artists: 0, albums: 0})
    property var columnErrors: ({})
    property var genres: []
    property var favorites: []
    property var favoriteQueries: ({songs: "", artists: "", albums: ""})
    property var selectedArtist: null
    property var selectedAlbum: null
    property var selectedSong: null
    property var artistDetail: ({})
    property var artistInfo: ({})
    property var albumTracks: []
    property var artistAlbumPaging: ({artistId: "", offset: 0, hasMore: false, loading: false})
    property var artistSongsPaging: ({artistId: "", cursor: "", albumOffset: 0, hasMore: false, loading: false})
    property string searchError: ""
    property string genreError: ""
    property string entityError: ""
    property string entityWarning: ""
    property string favoriteError: ""
    property string downloadError: ""
    readonly property bool downloadLoading: backendService.activeJobCount > 0
    onHostChanged: updateRetention()
    onVisibleChanged: { if (!visible) { activity.close(); lyricsDialog.close(); artistInfoDialog.close(); genrePopup.close(); } }
    onDownloadLoadingChanged: updateRetention()
    onSearchErrorChanged: { if (searchError) activity.notify(searchError, true); }
    onFavoriteErrorChanged: { if (favoriteError) activity.notify(favoriteError, true); }
    onEntityErrorChanged: { if (entityError) activity.notify(entityError, true); }
    onEntityWarningChanged: { if (entityWarning) activity.notify(entityWarning, false); }
    onDownloadErrorChanged: { if (downloadError) activity.notify(downloadError, true); }
    readonly property var torrentActivity: torrentService.jobs.map(job => ({
        job_id: "torrent:" + job.id, title: job.title, state: job.active ? "running" : job.status === "review" ? "review" : "finished",
        detail: job.message || job.status, total: job.total || 0, done: job.downloaded || 0, unit: "bytes",
        speed: job.speed || 0, eta: job.eta, cancellable: false, actionLabel: "Manage download", record: job.record, original: job
    }))
    property var downloadCapabilities: ({track: false, album: false})
    property alias playMessage: playback.playMessage
    property string lyricsTitle: ""
    property string lyricsText: ""
    property string lyricsProvider: ""
    property string lyricsError: ""
    property string artistInfoError: ""
    property alias ipcPath: playback.ipcPath
    property alias currentTrackKey: playback.currentTrackKey
    property alias currentTrack: playback.currentTrack
    property alias playerProcess: playback.playerProcess
    property alias queueSongs: playback.queueSongs
    property alias shuffleHistory: playback.shuffleHistory
    property alias queueScopeKey: playback.queueScopeKey
    property alias currentTrackIndex: playback.currentTrackIndex
    property int searchGeneration: 0
    property int entityGeneration: 0
    property alias playGeneration: playback.playGeneration
    property alias position: playback.position
    property alias duration: playback.duration
    property alias volume: playback.volume
    property alias playerPollPending: playback.playerPollPending
    property alias playerPaused: playback.playerPaused
    property alias shuffleEnabled: playback.shuffleEnabled
    property alias repeatAllEnabled: playback.repeatAllEnabled
    property bool loading: false
    property bool genresLoading: false
    property bool genresLoaded: false
    property bool favoritesLoading: true
    property bool entityLoading: false
    property bool lyricsLoading: false
    property bool artistInfoLoading: false
    property bool artistInfoAvailable: false
    property int lyricsGeneration: 0
    property int artistInfoGeneration: 0
    readonly property bool allSearchActive: section === "local" || (section === "discover" && !filtersView)
    readonly property var genreOptions: [{id: "", name: "All genres"}].concat(genres)
    readonly property var visibleGenres: genreOptions.filter(item => item.name.toLowerCase().includes(genreQuery.trim().toLowerCase()))
    readonly property var paneSpecs: [{kind: "songs", title: "Songs"}, {kind: "artists", title: "Artists"}, {kind: "albums", title: "Albums"}]
    spacing: 10

    MusicService {
        id: backendService
        onFailed: message => root.searchError = message
        onJobStartFailed: message => activity.notify(message, true)
        onJobFinished: job => {
            const result = job.result;
            if (job.error) activity.notify(job.error, job.state === "failed");
            else if (result && result.path) {
                activity.notify("Saved " + (result.saved || 1) + " tracks to " + result.path
                    + (result.failed ? "; " + result.failed + " could not be saved" : ""), !!result.failed);
                root.loadLocalSongs();
            } else activity.notify("Opened the download URL", false);
        }
    }

    function activate() {
        if (downloadLoading || torrentService.keepRunning) activity.open();
        if (section === "discover") searchField.focusField();
        else if (section === "local") songTable.focusList();
        else favoriteNavButton.forceActiveFocus();
    }

    function loadLocalSongs() {
        localLoading = true;
        searchError = "";
        backendService.request("local-songs", {}, (result, failure) => {
            localLoading = false;
            if (failure) searchError = failure;
            else localSongs = result;
        });
    }

    function findLocal(item, scope) {
        if (!item || !item.id) return;
        const generation = ++torrentGeneration;
        torrentTarget = Object.assign({}, item, {
            kind: "music",
            scope: scope,
            title: scope === "artist" ? item.name : item.title,
            artist: scope === "artist" ? item.name : item.artist,
            album: scope === "album" ? item.title : item.album || "",
            tracks: []
        });
        torrentTracksLoading = scope !== "song";
        torrentOpen = true;
        if (scope === "song") return;
        backendService.request(scope, {[scope]:item}, (result, failure) => {
            if (generation !== torrentGeneration) return;
            torrentTracksLoading = false;
            if (failure) { musicFinder.lookupError = failure; return; }
            torrentTarget = Object.assign({}, torrentTarget, {tracks: result.songs || []});
        });
    }

    function showLyrics(song) {
        if (!song) return;
        const generation = ++lyricsGeneration;
        lyricsTitle = song.title || "Unknown Title";
        lyricsText = "";
        lyricsProvider = "";
        lyricsError = "";
        lyricsLoading = true;
        lyricsDialog.open();
        backendService.request("lyrics", {song: song}, (result, failure) => {
            if (generation !== root.lyricsGeneration) return;
            root.lyricsLoading = false;
            if (failure) {
                root.lyricsError = failure;
                return;
            }
            root.lyricsText = result && result.available ? result.lyrics || "" : "";
            root.lyricsProvider = result && result.available ? result.provider || "" : "";
        });
    }

    function download(kind, item) {
        if (!item) return;
        backendService.startJob("download_start", {kind: kind, item: item, title: "Save " + (item.title || item.name || "music")});
    }

    function showArtistInfo(artist) {
        if (!artist) return;
        const generation = ++artistInfoGeneration;
        artistInfo = artist;
        artistInfoError = "";
        artistInfoLoading = true;
        artistInfoAvailable = false;
        artistInfoDialog.open();
        backendService.request("artist-info", {artist: artist}, (result, failure) => {
            if (generation !== root.artistInfoGeneration) return;
            root.artistInfoLoading = false;
            if (failure) {
                root.artistInfoError = failure;
                return;
            }
            root.artistInfo = result && result.artist || artist;
            root.artistInfoAvailable = !!(result && result.available);
        });
    }

    function recordKey(item) {
        return String(item && item.kind || "") + "|" + String(item && item.id || "");
    }

    function isFavorite(item) {
        if (!item || !item.kind || !item.id) return false;
        const key = recordKey(item);
        return !!key && favorites.some(value => recordKey(value) === key);
    }

    function categoryItems(kind) {
        return Array.isArray(results[kind]) ? results[kind] : [];
    }

    function setObjectValue(object, key, value) {
        const next = Object.assign({}, object || {});
        next[key] = value;
        return next;
    }

    function isSelected(kind, item) {
        if (kind === "artists") return !!selectedArtist && recordKey(selectedArtist) === recordKey(item);
        if (kind === "albums") return !!selectedAlbum && recordKey(selectedAlbum) === recordKey(item);
        return (!!selectedSong && recordKey(selectedSong) === recordKey(item))
            || currentTrackKey === recordKey(item);
    }

    function artistsForAlbum(album) {
        if (!album) return [];
        const names = Array.isArray(album.artists) && album.artists.length
            ? album.artists : [album.artist || "Unknown Artist"];
        const ids = Array.isArray(album.artistIds) ? album.artistIds.map(String) : [];
        const covers = Array.isArray(album.artistCovers) ? album.artistCovers : [];
        const count = Math.max(names.length, ids.length);
        const known = categoryItems("artists").concat(columnResults.artists || [], favorites.filter(item => item.kind === "artist"));
        const output = [];
        for (let index = 0; index < count; ++index) {
            const name = String(names[index] || "Unknown Artist");
            const id = ids[index] || "";
            const match = known.find(item => id
                ? String(item.id || "") === id
                : String(item.name || "").trim().toLocaleLowerCase() === name.trim().toLocaleLowerCase());
            output.push(match || {
                kind: "artist",
                id: id || "name:" + name.toLocaleLowerCase(),
                source: id ? (album.source || "apple") : "apple",
                name: name,
                cover: covers[index] || "",
                genres: []
            });
        }
        return output;
    }

    function albumForSong(song) {
        if (!song) return null;
        const albumId = String(song.albumId || "");
        const candidates = (columnResults.albums || []).concat(categoryItems("albums"), favorites.filter(item => item.kind === "album"));
        const found = candidates.find(item => (albumId && String(item.id || "") === albumId)
            || (String(item.title || "").trim().toLocaleLowerCase() === String(song.album || "").trim().toLocaleLowerCase()
                && String(item.artist || "").trim().toLocaleLowerCase() === String(song.artist || "").trim().toLocaleLowerCase()));
        if (found) return found;
        const title = String(song.album || "Unknown Album");
        return {
            kind: "album",
            id: albumId || "name:" + title.toLocaleLowerCase(),
            source: albumId ? (song.source || "apple") : "apple",
            title: title,
            artist: song.artist || "Unknown Artist",
            artists: song.artists || [song.artist || "Unknown Artist"],
            artistIds: song.artistIds || [],
            artistCovers: [song.artistCover || ""],
            cover: song.albumCover || song.cover || "",
            releaseDate: song.releaseDate || ""
        };
    }

    function artistsForSong(song) {
        if (!song) return [];
        const names = Array.isArray(song.artists) && song.artists.length ? song.artists : [song.artist || "Unknown Artist"];
        return artistsForAlbum({
            source: song.source || "apple",
            artists: names,
            artistIds: song.artistIds || [],
            artistCovers: names.map((name, index) => index === 0 ? song.artistCover || "" : "")
        });
    }

    function filterFavoriteItems(kind, items) {
        const query = String(favoriteQueries[kind] || "").trim().toLocaleLowerCase();
        if (!query) return items;
        return items.filter(item => {
            let fields = kind === "artists"
                ? [item.name]
                : kind === "albums"
                    ? [item.title, item.artist]
                    : [item.title, item.artist, item.album];
            if (Array.isArray(item.artists)) fields = fields.concat(item.artists);
            return fields.filter(Boolean).join(" ").toLocaleLowerCase().includes(query);
        });
    }

    function itemsFor(kind) {
        if (section === "local") {
            if (kind !== "songs") return [];
            const query = localQuery.trim().toLowerCase();
            return query ? localSongs.filter(song => [song.title, song.artist, song.album].some(value => String(value || "").toLowerCase().includes(query))) : localSongs;
        }
        if (section === "discover") {
            if (allSearchActive && kind === "songs") return categoryItems("songs");
            return Array.isArray(paneResults[kind]) ? paneResults[kind] : [];
        }
        const favoriteType = kind === "artists" ? "artist" : kind === "albums" ? "album" : "song";
        const source = selectedArtist || selectedAlbum || selectedSong
            ? (Array.isArray(paneResults[kind]) ? paneResults[kind] : [])
            : favorites.filter(item => item.kind === favoriteType);
        return filterFavoriteItems(kind, source);
    }

    function paneShowsFavorites(kind) {
        if (!selectedArtist && !selectedAlbum && !selectedSong) return true;
        if (selectedArtist) return kind === "artists";
        if (selectedAlbum) return kind === "albums";
        return kind === "songs";
    }

    function songScopeKey() {
        if (section === "local") return "local";
        if (section === "favorites") return "favorites:" + String(selectedArtist && selectedArtist.id || "") + ":" + String(selectedAlbum && selectedAlbum.id || "");
        if (allSearchActive) return "all:" + searchGeneration;
        if (selectedAlbum) return "album:" + String(selectedAlbum.id || "");
        if (selectedArtist) return "artist:" + String(selectedArtist.id || selectedArtist.name || "");
        return "songs-column:" + String(columnGenerations.songs || 0);
    }

    function hasMoreFor(kind) {
        if (section === "local") return false;
        if (kind === "albums" && selectedArtist && paneOverrides.albums)
            return !!artistAlbumPaging.hasMore;
        if (kind === "songs" && selectedArtist && paneOverrides.songs)
            return !!artistSongsPaging.hasMore;
        if (section === "favorites") return false;
        if (!allSearchActive && !!paneOverrides[kind]) return false;
        const state = allSearchActive ? (paging[kind] || {}) : (columnPaging[kind] || {});
        return !!state.hasMore;
    }

    function loadingMoreFor(kind) {
        if (kind === "albums" && selectedArtist && paneOverrides.albums)
            return !!artistAlbumPaging.loading;
        if (kind === "songs" && selectedArtist && paneOverrides.songs)
            return !!artistSongsPaging.loading;
        const state = allSearchActive ? (paging[kind] || {}) : (columnPaging[kind] || {});
        return !!state.loading;
    }

    function resetSelections() {
        ++entityGeneration;
        selectedArtist = null;
        selectedAlbum = null;
        selectedSong = null;
        artistDetail = ({});
        albumTracks = [];
        artistAlbumPaging = ({artistId: "", offset: 0, hasMore: false, loading: false});
        artistSongsPaging = ({artistId: "", cursor: "", albumOffset: 0, hasMore: false, loading: false});
        entityLoading = false;
        entityError = "";
        entityWarning = "";
    }

    function restorePaneResults() {
        if (section === "discover") paneResults = Object.assign({}, columnResults);
        paneOverrides = ({songs: false, artists: false, albums: false});
        resetSelections();
    }

    function clearColumnQuery(kind) {
        const nextQueries = setObjectValue(columnQueries, kind, "");
        columnQueries = nextQueries;
        columnGenerations = setObjectValue(columnGenerations, kind, (Number(columnGenerations[kind]) || 0) + 1);
        columnResults = setObjectValue(columnResults, kind, []);
        columnPaging = setObjectValue(columnPaging, kind, {limit: 0, hasMore: false, loading: false});
        columnErrors = setObjectValue(columnErrors, kind, "");
        paneOverrides = setObjectValue(paneOverrides, kind, false);
    }

    function clearFavoriteQuery(kind) {
        favoriteQueries = setObjectValue(favoriteQueries, kind, "");
    }

    function changeFavoriteQuery(kind, query) {
        favoriteQueries = setObjectValue(favoriteQueries, kind, String(query || ""));
    }

    function changeColumnQuery(kind, query) {
        const value = String(query || "");
        columnQueries = setObjectValue(columnQueries, kind, value);
        columnGenerations = setObjectValue(columnGenerations, kind, (Number(columnGenerations[kind]) || 0) + 1);
        columnResults = setObjectValue(columnResults, kind, []);
        paneResults = setObjectValue(paneResults, kind, []);
        columnPaging = setObjectValue(columnPaging, kind, {limit: 0, hasMore: false, loading: !!value.trim()});
        columnErrors = setObjectValue(columnErrors, kind, "");
        paneOverrides = setObjectValue(paneOverrides, kind, false);
    }

    function setPaneResults(kind, items) {
        paneResults = setObjectValue(paneResults, kind, items || []);
    }

    function setColumnSearchToEmpty(kind) {
        if (section === "discover") clearColumnQuery(kind);
        else if (section === "favorites") clearFavoriteQuery(kind);
    }

    function requestColumnSearch(kind) {
        if (section !== "discover") return;
        const query = String(columnQueries[kind] || "").trim();
        if (!query) return;
        const generation = Number(columnGenerations[kind]) || 0;
        const state = Object.assign({}, columnPaging[kind] || {}, {loading: true});
        columnPaging = setObjectValue(columnPaging, kind, state);
        backendService.request("search-page", {
            query: query,
            category: kind,
            offset: 0,
            limit: 25,
            includeReleaseMetadata: true
        }, (result, failure) => {
            if (generation !== Number(root.columnGenerations[kind])) return;
            const items = failure ? [] : (result && result.items || []);
            columnResults = setObjectValue(columnResults, kind, items);
            if (!paneOverrides[kind]) paneResults = setObjectValue(paneResults, kind, items);
            columnPaging = setObjectValue(columnPaging, kind, {
                limit: result && result.limit || 0,
                hasMore: !!(result && result.hasMore),
                loading: false
            });
            columnErrors = setObjectValue(columnErrors, kind, failure || "");
        });
    }

    function uniqueAppend(existing, additions) {
        const output = existing.slice();
        const seen = new Set(output.map(recordKey));
        for (const item of additions || []) {
            const key = recordKey(item);
            if (!key || seen.has(key)) continue;
            seen.add(key);
            output.push(item);
        }
        return output;
    }

    function appendUniqueAlbums(existing, additions) { return uniqueAppend(existing, additions); }

    function loadMoreArtistAlbums() {
        const state = artistAlbumPaging || ({});
        if (!state.hasMore || state.loading || !state.artistId) return;
        const generation = entityGeneration;
        artistAlbumPaging = Object.assign({}, state, {loading: true});
        backendService.request("artist-albums-page", {
            artistId: state.artistId,
            offset: state.offset || 0
        }, (result, failure) => {
            if (generation !== root.entityGeneration) return;
            artistAlbumPaging = Object.assign({}, root.artistAlbumPaging, {loading: false});
            if (failure) {
                entityError = failure;
                return;
            }
            setPaneResults("albums", appendUniqueAlbums(itemsFor("albums"), result && result.items || []));
            setPaneResults("songs", uniqueAppend(itemsFor("songs"), result && result.songs || []));
            if (result && result.trackWarning) entityWarning = result.trackWarning;
            if (queueScopeKey === songScopeKey()) {
                const updatedQueue = itemsFor("songs");
                const playingIndex = updatedQueue.findIndex(item => recordKey(item) === currentTrackKey);
                queueSongs = updatedQueue.slice();
                if (playingIndex >= 0) currentTrackIndex = playingIndex;
            }
            artistAlbumPaging = {
                artistId: state.artistId,
                offset: result && result.offset || state.offset || 0,
                hasMore: !!(result && result.hasMore),
                loading: false
            };
        });
    }

    function loadMoreArtistSongs() {
        const state = artistSongsPaging || ({});
        if (!state.hasMore || state.loading || !state.artistId) return;
        const generation = entityGeneration;
        artistSongsPaging = Object.assign({}, state, {loading: true});
        backendService.request("artist-songs-page", {
            artistId: state.artistId, cursor: state.cursor || "", albumOffset: state.albumOffset || 0
        }, (result, failure) => {
            if (generation !== root.entityGeneration) return;
            if (failure) {
                artistSongsPaging = Object.assign({}, root.artistSongsPaging, {loading: false, hasMore: false});
                entityError = failure;
                return;
            }
            setPaneResults("songs", uniqueAppend(itemsFor("songs"), result && result.items || []));
            if (result && result.trackWarning) entityWarning = result.trackWarning;
            if (queueScopeKey === songScopeKey()) {
                const updatedQueue = itemsFor("songs");
                const playingIndex = updatedQueue.findIndex(item => recordKey(item) === currentTrackKey);
                queueSongs = updatedQueue.slice();
                if (playingIndex >= 0) currentTrackIndex = playingIndex;
            }
            artistSongsPaging = {
                artistId: state.artistId, cursor: result && result.cursor || "",
                albumOffset: result && result.albumOffset || state.albumOffset || 0,
                hasMore: !!(result && result.hasMore), loading: false
            };
        });
    }

    function requestSearch() {
        const query = searchQuery.trim();
        const generation = ++searchGeneration;
        searchError = "";
        results = ({artists: [], albums: [], songs: []});
        paging = ({});
        loading = true;
        backendService.request("search", {
            query: query,
            kind: "all",
            genreId: selectedGenreId,
            genreName: selectedGenreName
        }, (result, failure) => {
            if (generation !== root.searchGeneration) return;
            loading = false;
            if (failure) {
                searchError = failure;
                results = ({artists: [], albums: [], songs: []});
                paging = ({});
                return;
            }
            results = result || ({artists: [], albums: [], songs: []});
            paging = result && result.paging || ({});
            searchError = "";
        });
    }

    function scheduleSearch() {
        ++searchGeneration;
        searchError = "";
        filtersView = false;
        if (!searchQuery.trim() && !selectedGenreId) {
            searchDelay.stop();
            requestSearch();
            return;
        }
        loading = true;
        searchDelay.restart();
    }

    function loadMore(kind) {
        if (kind === "albums" && selectedArtist && paneOverrides.albums) {
            loadMoreArtistAlbums();
            return;
        }
        if (kind === "songs" && selectedArtist && paneOverrides.songs) {
            loadMoreArtistSongs();
            return;
        }
        if (section !== "discover") return;
        const globalSearch = allSearchActive;
        const state = globalSearch ? (paging[kind] || {}) : (columnPaging[kind] || {});
        const query = globalSearch ? searchQuery.trim() : String(columnQueries[kind] || "").trim();
        if ((!globalSearch && !query) || !state.hasMore || state.loading) return;
        const oldLimit = Number(state.limit) || 0;
        const limit = Math.min(500, oldLimit + 25);
        if (limit <= oldLimit) return;
        const generation = globalSearch ? searchGeneration : Number(columnGenerations[kind]);
        const nextPaging = setObjectValue(globalSearch ? paging : columnPaging, kind, Object.assign({}, state, {loading: true}));
        if (globalSearch) paging = nextPaging;
        else columnPaging = nextPaging;
        backendService.request("search-page", {
            query: query,
            category: kind,
            offset: oldLimit,
            limit: limit,
            cursor: state.cursor || "",
            genreId: globalSearch ? selectedGenreId : "",
            genreName: globalSearch ? selectedGenreName : "",
            includeReleaseMetadata: true
        }, (result, failure) => {
            if (globalSearch && generation !== root.searchGeneration) return;
            if (!globalSearch && generation !== Number(root.columnGenerations[kind])) return;
            const currentPaging = Object.assign({}, globalSearch ? root.paging : root.columnPaging);
            const current = Object.assign({}, currentPaging[kind] || {});
            current.loading = false;
            if (failure) {
                current.hasMore = false;
                if (globalSearch) searchError = failure;
                else columnErrors = setObjectValue(columnErrors, kind, failure);
            } else {
                const added = result && result.items || [];
                if (globalSearch) {
                    const nextResults = Object.assign({}, root.results);
                    nextResults[kind] = uniqueAppend(categoryItems(kind), added);
                    results = nextResults;
                } else {
                    const appended = uniqueAppend(columnResults[kind] || [], added);
                    columnResults = setObjectValue(columnResults, kind, appended);
                    if (!paneOverrides[kind]) paneResults = setObjectValue(paneResults, kind, appended);
                }
                if (kind === "songs" && queueScopeKey === songScopeKey()) {
                    const updatedQueue = itemsFor("songs");
                    const playingIndex = updatedQueue.findIndex(item => recordKey(item) === currentTrackKey);
                    queueSongs = updatedQueue.slice();
                    if (playingIndex >= 0) currentTrackIndex = playingIndex;
                }
                current.limit = result && result.limit || limit;
                current.hasMore = !!(result && result.hasMore) && current.limit < 500;
                current.cursor = result && result.cursor || "";
                if (!added.length) current.hasMore = false;
            }
            currentPaging[kind] = current;
            if (globalSearch) paging = currentPaging;
            else columnPaging = currentPaging;
        });
    }

    function loadGenres() {
        if (genresLoading || genresLoaded) return;
        genresLoading = true;
        genreError = "";
        backendService.request("genres", {}, (result, failure) => {
            genresLoading = false;
            if (failure) {
                genreError = failure;
                return;
            }
            genres = Array.isArray(result) ? result : [];
            genresLoaded = true;
            genreError = "";
        });
    }

    function chooseGenre(item) {
        filtersView = false;
        selectedGenreId = item.id;
        selectedGenreName = item.id ? item.name : "";
        genrePopup.close();
        genreButton.forceActiveFocus();
        requestSearch();
    }

    function toggleFavorite(item) {
        if (!item || !item.kind || !item.id) return;
        const key = recordKey(item);
        if (isFavorite(item)) favorites = favorites.filter(value => recordKey(value) !== key);
        else favorites = [item].concat(favorites);
        persistFavorites();
    }

    function persistFavorites() {
        favoriteError = "";
        backendService.request("favorites-save", {favorites: favorites}, (result, failure) => {
            favoriteError = failure || "";
        });
    }

    function loadFavorites() {
        favoritesLoading = true;
        backendService.request("favorites-load", {}, (result, failure) => {
            favoritesLoading = false;
            favoriteError = failure || "";
            favorites = Array.isArray(result) ? result : [];
        });
    }

    function selectArtist(artist) {
        if (!artist) return;
        if (selectedArtist && recordKey(selectedArtist) === recordKey(artist)) {
            clearArtist();
            return;
        }
        const candidates = itemsFor("artists");
        if (section === "favorites" || !allSearchActive) setPaneResults("artists", candidates);
        setColumnSearchToEmpty("songs");
        setColumnSearchToEmpty("albums");
        const generation = ++entityGeneration;
        selectedArtist = artist;
        selectedAlbum = null;
        selectedSong = null;
        albumTracks = [];
        artistAlbumPaging = ({artistId: "", offset: 0, hasMore: false, loading: false});
        artistSongsPaging = ({artistId: "", cursor: "", albumOffset: 0, hasMore: false, loading: false});
        artistDetail = ({artist: artist, albums: [], songs: []});
        setPaneResults("songs", []);
        setPaneResults("albums", []);
        paneOverrides = setObjectValue(setObjectValue(paneOverrides, "songs", true), "albums", true);
        entityError = "";
        entityWarning = "";
        entityLoading = true;
        backendService.request("artist", {artist: artist}, (result, failure) => {
            if (generation !== root.entityGeneration) return;
            entityLoading = false;
            if (failure) {
                entityError = failure;
                return;
            }
            artistDetail = result || ({artist: artist, albums: [], songs: []});
            artistAlbumPaging = Object.assign(
                {artistId: "", offset: 0, hasMore: false, loading: false},
                result && result.albumPaging || {}
            );
            artistSongsPaging = Object.assign(
                {artistId: "", cursor: "", albumOffset: 0, hasMore: false, loading: false},
                result && result.songPaging || {}
            );
            entityWarning = result && result.trackWarning || "";
            if (paneOverrides.albums) setPaneResults("albums", artistDetail.albums || []);
            if (paneOverrides.songs) setPaneResults("songs", artistDetail.songs || []);
        });
    }

    function selectAlbum(album) {
        if (!album) return;
        if (selectedAlbum && recordKey(selectedAlbum) === recordKey(album)) {
            clearAlbum();
            return;
        }
        const candidates = itemsFor("albums");
        if (section === "favorites" || !allSearchActive) setPaneResults("albums", candidates);
        setColumnSearchToEmpty("songs");
        setColumnSearchToEmpty("artists");
        const generation = ++entityGeneration;
        selectedAlbum = album;
        selectedArtist = null;
        selectedSong = null;
        artistAlbumPaging = ({artistId: "", offset: 0, hasMore: false, loading: false});
        artistDetail = ({});
        albumTracks = [];
        setPaneResults("songs", []);
        setPaneResults("artists", artistsForAlbum(album));
        paneOverrides = setObjectValue(setObjectValue(paneOverrides, "songs", true), "artists", true);
        entityError = "";
        entityWarning = "";
        entityLoading = true;
        backendService.request("album", {album: album}, (result, failure) => {
            if (generation !== root.entityGeneration) return;
            entityLoading = false;
            if (failure) {
                entityError = failure;
                return;
            }
            albumTracks = result && result.songs || [];
            if (result && result.album) {
                selectedAlbum = Object.assign({}, album, result.album, {id: album.id, source: album.source});
                if (paneOverrides.artists) {
                    const relatedArtists = result.artists || [];
                    setPaneResults("artists", relatedArtists.length ? relatedArtists : artistsForAlbum(selectedAlbum));
                }
            }
            if (paneOverrides.songs) setPaneResults("songs", albumTracks);
        });
    }

    function selectSong(song, songs) {
        if (!song) return;
        torrentOpen = false;
        const visibleSongs = Array.isArray(songs) ? songs : itemsFor("songs");
        const generation = ++entityGeneration;
        entityLoading = false;
        selectedSong = song;
        selectedArtist = null;
        selectedAlbum = null;
        artistAlbumPaging = ({artistId: "", offset: 0, hasMore: false, loading: false});
        albumTracks = [];
        artistDetail = ({});
        entityError = "";
        entityWarning = "";
        setPaneResults("songs", visibleSongs);
        setPaneResults("artists", artistsForSong(song));
        const album = albumForSong(song);
        setPaneResults("albums", album ? [album] : []);
        paneOverrides = setObjectValue(setObjectValue(paneOverrides, "artists", true), "albums", true);
        if (section !== "local") backendService.request("song-artists", {song: song}, (result, failure) => {
            if (generation !== root.entityGeneration || failure || !Array.isArray(result) || !result.length) return;
            if (recordKey(root.selectedSong) !== recordKey(song)) return;
            setPaneResults("artists", result);
        });
    }

    function clearArtist() {
        restorePaneResults();
    }

    function clearAlbum() {
        restorePaneResults();
    }

    function clearSong() {
        restorePaneResults();
    }

    function seekTo(value) { playback.seekTo(value); }
    function changeVolume(value) { playback.changeVolume(value); }
    function togglePause() { playback.togglePause(); }
    function playSongs(songs, index) { playback.playSongs(songs, index); }
    function playTrackAt(index) { playback.playTrackAt(index); }
    function playNext(fromEnd) { playback.playNext(fromEnd); }
    function playPrevious() { playback.playPrevious(); }
    function stopPlayback() { playback.stopPlayback(); }

    function formatTime(value) {
        const seconds = Math.max(0, Math.floor(Number(value) || 0));
        const minutes = Math.floor(seconds / 60);
        const remainder = String(seconds % 60).padStart(2, "0");
        if (minutes >= 60) {
            const hours = Math.floor(minutes / 60);
            return hours + ":" + String(minutes % 60).padStart(2, "0") + ":" + remainder;
        }
        return minutes + ":" + remainder;
    }

    function popupBelow(button, popup) {
        // Clamp in module coordinates, then position relative to the trigger.
        const point = button.mapToItem(root, 0, button.height);
        popup.x = Math.max(0, Math.min(point.x, root.width - popup.width)) - point.x;
        popup.y = Math.max(0, Math.min(point.y + 5, root.height - popup.height)) - (point.y - button.height);
    }

    function showGenrePopup() {
        if (genrePopup.visible) { genrePopup.close(); return; }
        popupBelow(genreButton, genrePopup);
        genrePopup.open();
    }

    function emptyText(kind) {
        if (section === "local") return localLoading ? "Loading local songs…" : searchError ? "Local library unavailable. Try opening Local again." : "No local songs match this search.";
        if (searchError && allSearchActive) return "Catalogue unavailable. Use Retry above to try again.";
        if (columnErrors[kind] && section === "discover") return "These results could not load.";
        if (entityError && (selectedArtist || selectedAlbum)) return "Details could not load.";
        if (loading && allSearchActive) return "Searching…";
        if (allSearchActive) {
            if (selectedGenreName && !searchQuery.trim()) return "No results in " + selectedGenreName + ".";
            if (!searchQuery.trim()) return "No songs on the charts.";
            return "No matching songs found.";
        }
        if (section === "discover" && !allSearchActive && !!(columnPaging[kind] || {}).loading)
            return "Searching…";
        if (favoritesLoading && section === "favorites") return "Loading favorites…";
        const hasColumnQuery = section === "discover"
            ? !!String(columnQueries[kind] || "").trim()
            : section === "favorites" && !!String(favoriteQueries[kind] || "").trim();
        if (entityLoading && !hasColumnQuery && selectedAlbum && kind === "songs") return "Loading album tracks…";
        if (entityLoading && !hasColumnQuery && selectedArtist && (kind === "songs" || kind === "albums")) return "Loading artist releases…";
        if (section === "favorites") {
            if (hasColumnQuery)
                return (selectedArtist || selectedAlbum || selectedSong ? "No matching " : "No matching favorite ")
                    + kind + " found.";
            if (selectedArtist && kind !== "artists") return "No related " + kind + " were returned.";
            if (selectedAlbum && kind === "songs") return "No tracks were returned for this album.";
            return "No favorite " + kind + " yet.";
        }
        if (section === "discover" && !allSearchActive && !String(columnQueries[kind] || "").trim()) {
            if (selectedArtist && (kind === "songs" || kind === "albums")) return "No related " + kind + " were returned.";
            if (selectedAlbum && (kind === "songs" || kind === "artists"))
                return kind === "songs" ? "No tracks were returned for this album." : "No artists were returned for this album.";
            if (selectedSong && kind !== "songs") return "No related " + kind + " was found for this song.";
            return "Search for " + kind + " in this column.";
        }
        if (selectedArtist && kind !== "artists" && !String(columnQueries[kind] || "").trim())
            return "No related " + kind + " were returned.";
        if (selectedAlbum && kind === "songs" && !String(columnQueries[kind] || "").trim())
            return "No tracks were returned for this album.";
        return "No matching " + kind + " found.";
    }

    Component.onCompleted: {
        loadFavorites();
        requestSearch();
        backendService.request("download-capabilities", {}, (result, failure) => {
            if (failure) root.downloadError = failure;
            else root.downloadCapabilities = result || ({track: false, album: false});
        });
    }

    Timer {
        id: searchDelay
        interval: 350
        onTriggered: root.requestSearch()
    }

    MusicPlayback { id: playback; service: backendService; controller: root }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        spacing: 8

        W.Action {
            iconName: "folder-open"
            text: "Local"
            highlighted: root.section === "local"
            onClicked: {
                root.section = "local";
                root.filtersView = false;
                root.torrentOpen = false;
                root.resetSelections();
                root.loadLocalSongs();
                root.activate();
            }
        }

        W.Action {
            iconName: "globe"
            text: "Discover"
            highlighted: root.section === "discover"
            onClicked: {
                root.section = "discover";
                root.torrentOpen = false;
                root.filtersView = false;
                root.restorePaneResults();
                root.requestSearch();
                root.activate();
            }
        }
        W.Action {
            id: favoriteNavButton
            iconName: "star"
            text: "Favorites"
            highlighted: root.section === "favorites"
            onClicked: {
                root.section = "favorites";
                root.torrentOpen = false;
                root.filtersView = false;
                root.resetSelections();
                root.searchError = "";
                root.activate();
            }
        }
        Item { Layout.fillWidth: true; Layout.minimumWidth: 4 }
        MusicSearchInput {
            id: searchField
            visible: root.section === "discover" || root.section === "local"
            Layout.fillWidth: visible
            Layout.minimumWidth: visible ? 170 : 0
            Layout.preferredWidth: visible ? 330 : 0
            Layout.maximumWidth: visible ? 500 : 0
            Layout.preferredHeight: 42
            placeholderText: root.section === "local" ? "Search local songs…" : "Search artists, albums, or songs…"
            text: root.section === "local" ? root.localQuery : root.searchQuery
            onUserTextEdited: value => {
                if (root.section === "local") { root.localQuery = value; return; }
                root.searchQuery = value;
                root.scheduleSearch();
            }
            onAccepted: {
                if (root.section === "local") { songTable.focusList(); return; }
                searchDelay.stop();
                root.filtersView = false;
                root.requestSearch();
            }
            onDownPressed: {
                if (root.allSearchActive)
                    songTable.focusList();
            }
        }
        W.IconButton {
            id: filtersButton
            visible: root.section === "discover"
            Layout.minimumWidth: visible ? 42 : 0
            Layout.maximumWidth: visible ? 42 : 0
            iconName: "sliders-horizontal"
            text: root.filtersView ? "Close filters" : "Filters"
            highlighted: root.filtersView
            onClicked: root.filtersView = !root.filtersView
        }
        W.Action {
            id: genreButton
            visible: root.section === "discover"
            Layout.preferredWidth: visible ? 132 : 0
            Layout.minimumWidth: visible ? 112 : 0
            iconName: "music"
            text: root.selectedGenreName || "All genres"
            Accessible.name: "Genre filter: " + text
            onClicked: root.showGenrePopup()
        }
        W.Action { iconName: "download"; text: backendService.activeJobCount + root.torrentActivity.filter(j => j.state === "running").length > 0 ? "Transfers (" + (backendService.activeJobCount + root.torrentActivity.filter(j => j.state === "running").length) + ")" : "Activity"; onClicked: activity.open() }
        W.BusySpinner {
            visible: root.section === "discover" && root.loading
            running: visible
            Layout.preferredWidth: visible ? 28 : 0
            Layout.preferredHeight: 28
        }
    }

    M.TorrentService {
        id: torrentService
        monitorKind: "music"
        monitorJobs: true
        onKeepRunningChanged: root.updateRetention()
        onLibraryChanged: root.loadLocalSongs()
        onJobsErrorChanged: { if (jobsError && jobs.some(j => j.active)) activity.notify(jobsError, true); }
    }
    W.OperationCenter {
        id: activity
        notificationTitle: "Music"
        parent: root
        jobs: backendService.jobs.concat(root.torrentActivity)
        retryAvailable: !!root.searchError || !!root.favoriteError
        onRetryRequested: { if (root.section === "favorites") root.persistFavorites(); else root.requestSearch(); }
        onCancelRequested: jobId => backendService.cancelJob(jobId)
        onActionRequested: job => {
            if (!String(job.job_id).startsWith("torrent:")) { backendService.retryJob(job.job_id); return; }
            root.torrentTarget = job.record || {id: job.original.titleId, kind: "music", title: job.title};
            root.torrentOpen = true;
            musicFinder.showJobPanel();
        }
    }

    MusicSongTable {
        id: songTable
        visible: root.allSearchActive && !root.torrentOpen
        Layout.fillWidth: true
        Layout.fillHeight: true
        controller: root
    }

    RowLayout {
        visible: root.paneSpecs.length > 0 && !root.allSearchActive && !root.torrentOpen
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8
        Repeater {
            model: root.paneSpecs
            delegate: MusicResultPane {
                required property var modelData
                controller: root
                kind: modelData.kind
                title: modelData.title
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: modelData.kind === "songs" ? 440 : 300
                Layout.minimumWidth: 130
            }
        }
    }
    M.TorrentSearch {
        host: root.host
        service: torrentService
        popupActivity: true
        id: musicFinder
        objectName: "musicTorrentSearch"
        visible: root.torrentOpen && !!root.torrentTarget.id
        Layout.fillWidth: true; Layout.fillHeight: true
        title: root.torrentTarget
        tracksLoading: root.torrentTracksLoading
        onTrackLookupRequested: query => {
            if (!query) return;
            const generation = root.torrentGeneration;
            musicFinder.lookupError = "";
            root.torrentTracksLoading = true;
            backendService.request("search", {query:query,kind:"songs"}, (result, failure) => {
                if (generation !== root.torrentGeneration) return;
                root.torrentTracksLoading = false;
                if (failure) { musicFinder.lookupError = failure; return; }
                root.torrentTarget = Object.assign({}, root.torrentTarget, {tracks:result.songs || []});
            });
        }
        onImported: root.loadLocalSongs()
    }

    Rectangle {
        visible: !!root.currentTrack
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 92 : 0
        radius: Theme.controlRadius
        color: Theme.surface
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 6
            anchors.bottomMargin: 5
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 7
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 3
                    color: Theme.raised
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.currentTrack && root.currentTrack.cover || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    W.Label {
                        Layout.fillWidth: true
                        text: root.currentTrack && root.currentTrack.title || ""
                        font.family: Theme.font; font.pixelSize: Theme.sp(13)
                        elide: Text.ElideRight
                    }
                    W.Label {
                        Layout.fillWidth: true
                        text: root.playMessage && root.playMessage !== "Playing"
                            ? root.playMessage
                            : (root.currentTrack && root.currentTrack.artist || "")
                        color: {
                            const message = root.playMessage.toLowerCase();
                            return message.includes("could not") || message.includes("install mpv")
                                || message.includes("stream ended") ? Theme.danger : Theme.muted;
                        }
                        font.family: Theme.font; font.pixelSize: Theme.sp(11)
                        elide: Text.ElideRight
                    }
                }
                W.IconButton {
                    iconName: "skip-back"
                    iconSize: 20
                    text: "Previous track"
                    enabled: root.queueSongs.length > 0
                    onClicked: root.playPrevious()
                }
                W.IconButton {
                    iconName: root.playerPaused ? "play" : "pause"
                    iconSize: 20
                    text: root.playerPaused ? "Play" : "Pause"
                    onClicked: root.togglePause()
                }
                W.IconButton {
                    iconName: "skip-forward"
                    iconSize: 20
                    text: "Next track"
                    enabled: root.queueSongs.length > 0
                    onClicked: root.playNext(false)
                }
                W.IconButton {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    iconName: root.shuffleEnabled ? "shuffle-active" : "shuffle"
                    iconSize: 18
                    text: root.shuffleEnabled ? "Shuffle on" : "Shuffle off"
                    onClicked: root.shuffleEnabled = !root.shuffleEnabled
                }
                W.IconButton {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    iconName: root.repeatAllEnabled ? "repeat-active" : "repeat"
                    iconSize: 18
                    text: root.repeatAllEnabled ? "Repeat all on" : "Repeat all off"
                    onClicked: root.repeatAllEnabled = !root.repeatAllEnabled
                }
                W.IconButton {
                    iconName: "square"
                    iconSize: 18
                    text: "Stop"
                    onClicked: root.stopPlayback()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                W.Label { text: root.formatTime(root.position); color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
                Slider {
                    id: playbackSlider
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, root.duration)
                    value: Math.min(root.position, to)
                    enabled: !!root.playerProcess && root.duration > 0
                    onPressedChanged: {
                        if (!pressed) root.seekTo(value);
                    }
                }
                W.Label { text: root.formatTime(root.duration); color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11) }
                W.Icon { name: "volume-2"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Slider {
                    Layout.preferredWidth: 96
                    from: 0
                    to: 100
                    value: root.volume
                    onPressedChanged: {
                        if (!pressed) root.changeVolume(value);
                    }
                }
            }
        }
    }

    Dialog {
        id: lyricsDialog
        parent: root
        x: Math.max(0, (root.width - width) / 2)
        y: Math.max(0, (root.height - height) / 2)
        width: Math.min(640, Math.max(280, root.width - 28))
        height: Math.min(580, Math.max(260, root.height - 28))
        modal: true
        focus: true
        title: "Lyrics"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            W.Action {
                text: "Close"
                highlighted: true
                onClicked: lyricsDialog.close()
            }
        }
        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            radius: Theme.controlRadius
        }
        contentItem: ColumnLayout {
            spacing: 8
            W.Label {
                Layout.fillWidth: true
                text: root.lyricsTitle
                font.family: Theme.font; font.pixelSize: Theme.sp(16)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                W.BusySpinner {
                    anchors.centerIn: parent
                    running: root.lyricsLoading
                    visible: running
                }
                W.Label {
                    anchors.fill: parent
                    visible: !root.lyricsLoading && !!root.lyricsError
                    text: root.lyricsError
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    verticalAlignment: Text.AlignVCenter
                }
                ScrollView {
                    anchors.fill: parent
                    visible: !root.lyricsLoading && !root.lyricsError
                    contentWidth: availableWidth
                    clip: true
                    TextArea {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: root.lyricsText || "No lyrics available"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.sp(14)
                        background: Item {}
                    }
                }
            }
            W.Label {
                visible: !root.lyricsLoading && !root.lyricsError && !!root.lyricsProvider
                Layout.fillWidth: true
                text: "Lyrics from " + root.lyricsProvider
                color: Theme.muted
                font.family: Theme.font; font.pixelSize: Theme.sp(11)
            }
        }
    }

    Dialog {
        id: artistInfoDialog
        parent: root
        x: Math.max(0, (root.width - width) / 2)
        y: Math.max(0, (root.height - height) / 2)
        width: Math.min(640, Math.max(280, root.width - 28))
        height: Math.min(580, Math.max(260, root.height - 28))
        modal: true
        focus: true
        title: root.artistInfo && root.artistInfo.name || "Artist information"
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            W.Action {
                text: "Close"
                highlighted: true
                onClicked: artistInfoDialog.close()
            }
        }
        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            radius: Theme.controlRadius
        }
        contentItem: ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: width / 2
                    color: Theme.raised
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.artistInfo && root.artistInfo.cover || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    W.Label {
                        Layout.fillWidth: true
                        text: root.artistInfo && root.artistInfo.name || "Unknown Artist"
                        font.family: Theme.font; font.pixelSize: Theme.sp(17)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    W.Label {
                        visible: !!(root.artistInfo && root.artistInfo.genres && root.artistInfo.genres.length)
                        Layout.fillWidth: true
                        text: root.artistInfo && root.artistInfo.genres
                            ? root.artistInfo.genres.join(" · ") : ""
                        color: Theme.muted
                        wrapMode: Text.Wrap
                    }
                    W.Action {
                        visible: !!(root.artistInfo && root.artistInfo.url)
                        iconName: "music"
                        text: "Open in Apple Music"
                        onClicked: Browser.open(root.artistInfo.url, "music", "", root.host)
                    }
                }
            }
            RowLayout {
                visible: root.artistInfoLoading
                Layout.fillWidth: true
                Layout.fillHeight: true
                W.BusySpinner { running: parent.visible; Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter }
            }
            W.Label {
                visible: !root.artistInfoLoading && !!root.artistInfoError
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.artistInfoError
                color: Theme.danger
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
            }
            ScrollView {
                visible: !root.artistInfoLoading && !root.artistInfoError
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 8
                    W.Label {
                        visible: !!(root.artistInfo && root.artistInfo.editorialNotes
                            && root.artistInfo.editorialNotes.tagline)
                        Layout.fillWidth: true
                        text: root.artistInfo && root.artistInfo.editorialNotes
                            ? root.artistInfo.editorialNotes.tagline || "" : ""
                        font.family: Theme.font; font.pixelSize: Theme.sp(14)
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }
                    W.Label {
                        visible: !!(root.artistInfo && (root.artistInfo.biography
                            || (root.artistInfo.editorialNotes
                                && (root.artistInfo.editorialNotes.standard || root.artistInfo.editorialNotes.short))))
                        Layout.fillWidth: true
                        text: "About"
                        font.family: Theme.font; font.pixelSize: Theme.sp(14)
                        font.weight: Font.DemiBold
                    }
                    W.Label {
                        visible: !!(root.artistInfo && ((root.artistInfo.editorialNotes
                            && (root.artistInfo.editorialNotes.standard || root.artistInfo.editorialNotes.short))
                            || root.artistInfo.biography))
                        Layout.fillWidth: true
                        text: {
                            if (!root.artistInfo) return "";
                            const notes = root.artistInfo.editorialNotes || {};
                            return root.artistInfo.biography || notes.standard || notes.short || "";
                        }
                        color: Theme.text
                        wrapMode: Text.Wrap
                    }
                    W.Label {
                        visible: !root.artistInfoLoading && !root.artistInfoAvailable
                        Layout.fillWidth: true
                        text: "No additional catalog information is available for this artist."
                        color: Theme.muted
                        wrapMode: Text.Wrap
                    }
                    W.Label {
                        visible: root.artistInfoAvailable
                        Layout.fillWidth: true
                        text: "Artist information from Apple Music"
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.sp(11)
                    }
                }
            }
        }
    }

    Popup {
        id: genrePopup
        parent: genreButton
        popupType: Popup.Item
        width: 300
        height: Math.min(420, root.height - 16)
        padding: 8
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: {
            root.loadGenres();
            genreSearch.text = "";
            root.genreQuery = "";
            genreList.currentIndex = 0;
            genreSearch.forceActiveFocus();
        }
        onClosed: genreButton.forceActiveFocus()
        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            radius: Theme.controlRadius
        }
        contentItem: ColumnLayout {
            spacing: 7
            W.Label {
                Layout.fillWidth: true
                text: "Genres"
                font.family: Theme.font; font.pixelSize: Theme.sp(14)
                font.weight: Font.DemiBold
            }
            W.SearchField {
                id: genreSearch
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                placeholderText: "Filter genres…"
                onTextChanged: {
                    root.genreQuery = text;
                    genreList.currentIndex = root.visibleGenres.length ? 0 : -1;
                }
                Keys.onDownPressed: (event) => {
                    genreList.forceActiveFocus();
                    event.accepted = true;
                }
            }
            W.Label {
                visible: root.genresLoading
                Layout.fillWidth: true
                text: "Loading genres…"
                color: Theme.muted
            }
            W.Label {
                visible: !!root.genreError && root.genresLoading === false && !root.genresLoaded
                Layout.fillWidth: true
                text: root.genreError
                color: Theme.danger
                wrapMode: Text.Wrap
            }
            W.Action {
                visible: !!root.genreError && !root.genresLoading && !root.genresLoaded
                text: "Retry"
                onClicked: root.loadGenres()
            }
            ListView {
                id: genreList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.genresLoading
                clip: true
                model: root.visibleGenres
                keyNavigationEnabled: true
                currentIndex: root.visibleGenres.length ? 0 : -1
                W.WheelScroll { view: genreList }
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    id: genreOption
                    required property var modelData
                    required property int index
                    width: genreList.width
                    height: 36
                    highlighted: genreList.currentIndex === index
                    contentItem: W.Label {
                        text: genreOption.modelData.name
                        color: genreOption.highlighted ? Theme.accent : Theme.text
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: genreOption.highlighted || genreOption.hovered ? Theme.raised : "transparent"
                        radius: Theme.controlRadius
                    }
                    onClicked: root.chooseGenre(modelData)
                }
                Keys.onReturnPressed: (event) => {
                    if (currentIndex >= 0) root.chooseGenre(root.visibleGenres[currentIndex]);
                    event.accepted = true;
                }
                Keys.onEnterPressed: (event) => {
                    if (currentIndex >= 0) root.chooseGenre(root.visibleGenres[currentIndex]);
                    event.accepted = true;
                }
            }
            W.Label {
                visible: root.genresLoaded && !root.visibleGenres.length
                Layout.fillWidth: true
                text: "No matching genres."
                color: Theme.muted
            }
        }
    }
}
