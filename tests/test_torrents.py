import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch

from media.local import destination
from media.scanner import guess
from media.torrent_backend import (
    QBitClient,
    QBitConnectionError,
    TorrentBackend,
    TorrentError,
    result_row,
    search_query,
)


class FakeQBit:
    def __init__(self):
        self.save_path = ""
        self.files = []
        self.calls = []

    def call(self, path, values=None):
        self.calls.append((path, values))
        if path == "search/plugins":
            return [{"name": "public", "enabled": True}]
        if path == "search/start":
            return {"id": 42}
        if path.startswith("search/results"):
            return {
                "results": [
                    {
                        "fileName": "The General (1998)",
                        "fileUrl": "magnet:?xt=urn:btih:abc",
                        "nbSeeders": 8,
                    }
                ],
                "status": "Stopped",
                "total": 1,
            }
        if path.startswith("search/status"):
            return [{"id": 1907502276, "status": "Running", "total": 145}]
        if path == "torrents/add":
            self.save_path = values["savepath"]
            return "Ok."
        if path == "torrents/fetchMetadata":
            return {
                "info": {"files": [{"path": file["name"], "length": 100} for file in self.files]}
            }
        if path == "torrents/delete":
            if values.get("deleteFiles") == "true":
                for file in self.files:
                    (Path(self.save_path) / file["name"]).unlink(missing_ok=True)
            self.save_path = ""
            return ""
        if path == "torrents/renameFile":
            old = Path(self.save_path) / values["oldPath"]
            new = Path(self.save_path) / values["newPath"]
            new.parent.mkdir(parents=True, exist_ok=True)
            old.rename(new)
            for file in self.files:
                if file["name"] == values["oldPath"]:
                    file["name"] = values["newPath"]
            return ""
        if path == "torrents/setLocation":
            new_root = Path(values["location"])
            for file in self.files:
                source = Path(self.save_path) / file["name"]
                target = new_root / file["name"]
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.is_file():
                    shutil.move(source, target)
            self.save_path = str(new_root)
            return ""
        if path == "torrents/setAutoManagement":
            return ""
        if path == "torrents/info":
            return (
                [
                    {
                        "save_path": self.save_path,
                        "progress": 1,
                        "hash": "a" * 40,
                        "name": "The General 1926 WEB-DL",
                    }
                ]
                if self.save_path
                else []
            )
        if path.startswith("torrents/files"):
            return self.files
        raise AssertionError(path)


class TorrentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = patch.dict(
            os.environ,
            {
                "XDG_VIDEOS_DIR": str(self.root / "Videos"),
                "XDG_MUSIC_DIR": str(self.root / "Music"),
                "XDG_DOCUMENTS_DIR": str(self.root / "Documents"),
                "XDG_DATA_HOME": str(self.root / "data"),
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        self.movie = {
            "id": "tt0017925",
            "imdbId": "tt0017925",
            "tmdbId": 961,
            "kind": "movie",
            "title": "The General",
            "year": 1926,
        }
        self.fake = FakeQBit()
        self.backend = TorrentBackend(
            self.root / "config/torrents.json", self.root / "data/zephyrus-shell/media", self.fake
        )

    def test_probe_only_offers_start_for_missing_local_process(self):
        with (
            patch.object(
                self.backend, "init", side_effect=QBitConnectionError("Web UI unreachable")
            ),
            patch.object(self.backend, "qbit_running", return_value=False),
            patch.object(self.backend, "qbit_launcher", return_value=["/usr/bin/qbittorrent"]),
        ):
            self.assertTrue(self.backend.handle({"op": "probe"})["canStart"])
            self.backend.config_path.parent.mkdir(parents=True)
            self.backend.config_path.write_text(json.dumps({"url": "http://example.org:8080"}))
            self.assertFalse(self.backend.handle({"op": "probe"})["canStart"])
            self.backend.config_path.write_text(json.dumps({"url": "http://127.0.0.1:8080"}))
            with patch.object(self.backend, "qbit_running", return_value=True):
                self.assertFalse(self.backend.handle({"op": "probe"})["canStart"])
            with patch.object(self.backend, "qbit_launcher", return_value=None):
                self.assertFalse(self.backend.handle({"op": "probe"})["canStart"])
        with patch.object(self.backend, "init", side_effect=TorrentError("Invalid credentials")):
            with self.assertRaisesRegex(TorrentError, "Invalid credentials"):
                self.backend.handle({"op": "probe"})

    def test_start_qbittorrent_uses_installed_launcher_only_for_local_web_ui(self):
        with (
            patch.object(self.backend, "qbit_running", return_value=False),
            patch.object(self.backend, "qbit_launcher", return_value=["/usr/bin/qbittorrent"]),
            patch("media.torrent_backend.subprocess.Popen") as launch,
        ):
            self.assertTrue(self.backend.handle({"op": "start_qbittorrent"})["started"])
            launch.assert_called_once_with(
                ["/usr/bin/qbittorrent"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            self.backend.config_path.parent.mkdir(parents=True)
            self.backend.config_path.write_text(json.dumps({"url": "http://example.org:8080"}))
            with self.assertRaisesRegex(TorrentError, "Only a local"):
                self.backend.handle({"op": "start_qbittorrent"})
            launch.assert_called_once()
            self.backend.config_path.write_text(json.dumps({"url": "http://127.0.0.1:8080"}))
            with patch.object(self.backend, "qbit_running", return_value=True):
                self.assertFalse(self.backend.handle({"op": "start_qbittorrent"})["started"])
            launch.assert_called_once()

    def test_flatpak_launcher_is_supported(self):
        with (
            patch(
                "media.torrent_backend.shutil.which",
                side_effect=lambda name: "/usr/bin/flatpak" if name == "flatpak" else None,
            ),
            patch("media.torrent_backend.subprocess.run") as installed,
        ):
            installed.return_value.returncode = 0
            self.assertEqual(
                TorrentBackend.qbit_launcher(),
                ["/usr/bin/flatpak", "run", "org.qbittorrent.qBittorrent"],
            )

    def test_network_failure_is_distinct_from_web_ui_rejection(self):
        client = QBitClient({"url": "http://127.0.0.1:8080"})
        with patch.object(client.opener, "open", side_effect=urllib.error.URLError("offline")):
            with self.assertRaises(QBitConnectionError):
                client.call("search/plugins")

    def test_context_search_and_wrong_year(self):
        self.assertEqual(search_query(self.movie), "The General 1926")
        self.assertTrue(result_row({"fileName": "The General (1998)"}, self.movie)["yearMismatch"])
        self.assertFalse(
            result_row({"fileName": "The General 1926 1080p"}, self.movie)["yearMismatch"]
        )
        result = self.backend.handle({"op": "search", "title": self.movie})
        self.assertEqual(result["id"], 42)
        self.assertEqual(self.fake.calls[-1][1]["pattern"], "The General 1926")
        episode = {
            "id": "tt9",
            "kind": "tv",
            "title": "Example",
            "year": 2020,
            "season": 1,
            "episode": 2,
        }
        self.assertEqual(search_query(episode), "Example S01E02")
        self.assertTrue(result_row({"fileName": "Example 2020 S01E03"}, episode)["episodeMismatch"])
        self.assertEqual(
            search_query(
                {
                    "kind": "music",
                    "scope": "song",
                    "title": "Prelude",
                    "artist": "A Writer",
                    "releaseDate": "2020-07-03",
                }
            ),
            "A Writer Prelude 2020",
        )
        self.assertEqual(
            search_query(
                {
                    "kind": "music",
                    "scope": "album",
                    "title": "First Album",
                    "artist": "A Writer",
                    "releaseDate": "2020-07-03",
                }
            ),
            "A Writer First Album 2020",
        )
        self.assertEqual(
            search_query(
                {"kind": "music", "scope": "artist", "title": "A Writer", "artist": "A Writer"}
            ),
            "A Writer discography",
        )
        self.assertEqual(
            search_query({"kind": "tv", "id": "tt9", "title": "Example", "year": 2020}),
            "Example complete",
        )
        self.assertEqual(
            search_query(
                {"kind": "tv", "id": "tt9", "title": "Example", "year": 2020, "season": 2}
            ),
            "Example S02",
        )
        self.assertTrue(
            result_row({"fileName": "Example S01E01"}, {"kind": "tv", "season": 2})[
                "seasonMismatch"
            ]
        )

    def test_results_uses_qbittorrent_job_id_not_worker_request_id(self):
        self.backend.handle(
            {"op": "results", "id": 7, "job_id": 1907502276, "title": self.movie, "offset": 0}
        )
        self.assertEqual(self.fake.calls[-1][0], "search/results?id=1907502276&limit=100&offset=0")
        self.assertEqual(
            self.backend.handle({"op": "status", "id": 8, "job_id": 1907502276}),
            {"running": True, "total": 145},
        )
        self.assertEqual(self.fake.calls[-1][0], "search/status?id=1907502276")

    def test_completed_movie_import_moves_seeding_source_and_ids(self):
        queued = self.backend.handle(
            {"op": "queue", "title": self.movie, "url": "magnet:?xt=urn:btih:abc"}
        )
        source = Path(self.fake.save_path) / "The.General.1926.mkv"
        source.write_bytes(b"video" * 250000)
        subtitle = source.with_suffix(".srt")
        language_subtitle = source.with_name(source.stem + "-bg.srt")
        added_later = source.with_name(source.stem + ".en.srt")
        for path in (subtitle, language_subtitle):
            path.write_text("subtitle")
        added_later.write_text("later subtitle")
        self.fake.files = [
            {"name": path.name, "priority": 1} for path in (source, subtitle, language_subtitle)
        ]
        jobs = self.backend.handle({"op": "jobs"})
        self.assertEqual(jobs[0]["status"], "imported")
        target = destination(self.movie, source)
        self.assertFalse(source.exists())
        self.assertTrue(target.is_file())
        self.assertTrue(target.with_suffix(".srt").is_file())
        self.assertTrue(target.with_name(target.stem + "-bg.srt").is_file())
        self.assertEqual(target.with_name(target.stem + ".en.srt").read_text(), "later subtitle")
        self.assertFalse(subtitle.exists())
        self.assertFalse(added_later.exists())
        self.assertIn(
            (
                "torrents/renameFile",
                {
                    "hash": "a" * 40,
                    "oldPath": language_subtitle.name,
                    "newPath": target.stem + "-bg.srt",
                },
            ),
            self.fake.calls,
        )
        self.assertFalse(
            any(
                path == "torrents/renameFile" and values["oldPath"] == added_later.name
                for path, values in self.fake.calls
            )
        )
        self.assertIn(
            ("torrents/setLocation", {"hashes": "a" * 40, "location": str(target.parent)}),
            self.fake.calls,
        )
        self.assertEqual(self.backend.library.files(self.movie)[0]["path"], str(target))
        nfo = (target.parent / "movie.nfo").read_text()
        self.assertIn("tt0017925", nfo)
        self.assertIn("961", nfo)
        self.assertIn("The General 1926 WEB-DL", nfo)
        self.assertIn("The.General.1926.mkv", nfo)
        self.assertIn("qBittorrent", nfo)
        self.assertEqual(
            self.backend.handle({"op": "local_list", "kind": "movie"})[0]["id"], self.movie["id"]
        )
        self.assertEqual(jobs[0]["id"], queued["id"])

    def test_series_names_episodes_and_keeps_other_title_separate(self):
        title = {"id": "tt9", "imdbId": "tt9", "kind": "tv", "title": "Example", "year": 2020}
        library = self.backend.library
        source = self.root / "source-S02E03.mkv"
        source.write_bytes(b"video")
        target = library.add(title, source)
        self.assertTrue(Path(target).name.endswith("S02E03.mkv"))
        self.assertIn("/Series/Example (2020)/Season 02/", target)
        self.assertTrue((Path(target).parent.parent / "tvshow.nfo").is_file())
        self.assertIn("tt9", (Path(target).parent.parent / "tvshow.nfo").read_text())
        self.assertEqual(library.files(title)[0]["episode"], 3)
        self.assertEqual(library.files(title | {"id": "tt-other", "imdbId": "tt-other"}), [])
        self.assertEqual(library.files({"kind": "tv", "title": "Unknown"}), [])
        self.assertEqual(library.files({"kind": "tv", "id": "tt-other"}), [])

    def test_ambiguous_movie_requires_explicit_file(self):
        queued = self.backend.handle(
            {"op": "queue", "title": self.movie, "url": "magnet:?xt=urn:btih:abc"}
        )
        staging = Path(self.fake.save_path)
        for name in ("The.General.1926.mkv", "The.General.1998.mkv"):
            (staging / name).write_bytes(b"video" * 250000)
        self.fake.files = [
            {"name": name, "priority": 1}
            for name in ("The.General.1926.mkv", "The.General.1998.mkv")
        ]
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "review")
        files = self.backend.handle({"op": "review", "job_id": queued["id"]})
        self.assertEqual(len(files), 2)
        self.backend.handle(
            {"op": "import_selected", "job_id": queued["id"], "path": "The.General.1926.mkv"}
        )
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "imported")

    def test_movie_content_year_mismatch_requires_review(self):
        self.backend.handle({"op": "queue", "title": self.movie, "url": "magnet:?xt=urn:btih:abc"})
        source = Path(self.fake.save_path) / "The.General.1998.mkv"
        source.write_bytes(b"video" * 250000)
        self.fake.files = [{"name": source.name, "priority": 1}]
        jobs = self.backend.handle({"op": "jobs"})
        self.assertEqual(jobs[0]["status"], "review")
        self.assertIn("different year", jobs[0]["message"])
        self.assertFalse(destination(self.movie, source).exists())

    def test_flat_music_name_and_discover_playback_use_local_file(self):
        from plugins.music.backend import resolve_track

        song = {
            "id": "apple-42",
            "kind": "music",
            "title": "Prelude",
            "artist": "Example Artist",
            "album": "Example Album",
            "releaseDate": "2020-07-03",
        }
        source = self.root / "track.flac"
        source.write_bytes(b"audio")
        path = self.backend.library.add(song, source)
        self.assertEqual(
            Path(path).name, "Prelude - Example Artist - Example Album (2020-07-03).flac"
        )
        self.assertEqual(resolve_track(song | {"kind": "song"})["url"], path)
        self.assertTrue(Path(path + ".zephyrus.json").is_file())
        with self.assertRaisesRegex(ValueError, "full release date"):
            destination(song | {"releaseDate": ""}, source)

    def test_album_download_matches_each_audio_file_to_catalogue_track(self):
        tracks = [
            {
                "kind": "song",
                "id": "apple-1",
                "title": "First",
                "artist": "Example",
                "album": "Album",
                "releaseDate": "2020-07-03",
            },
            {
                "kind": "song",
                "id": "apple-2",
                "title": "Second",
                "artist": "Example",
                "album": "Album",
                "releaseDate": "2020-07-03",
            },
        ]
        album = {
            "kind": "music",
            "scope": "album",
            "id": "apple-album",
            "title": "Album",
            "artist": "Example",
            "releaseDate": "2020-07-03",
            "tracks": tracks,
        }
        queued = self.backend.handle(
            {"op": "queue", "title": album, "url": "magnet:?xt=urn:btih:abc"}
        )
        staging = Path(self.fake.save_path)
        for name in ("01.flac", "02.flac"):
            (staging / name).write_bytes(b"audio")
        self.fake.files = [{"name": name, "priority": 1} for name in ("01.flac", "02.flac")]
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "review")
        self.assertEqual(len(self.backend.handle({"op": "review", "job_id": queued["id"]})), 2)
        first = self.backend.handle(
            {"op": "import_selected", "job_id": queued["id"], "path": "01.flac", "track": tracks[0]}
        )
        self.assertEqual(first["remaining"], 1)
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "review")
        self.assertEqual(
            [
                item["path"]
                for item in self.backend.handle({"op": "review", "job_id": queued["id"]})
            ],
            ["02.flac"],
        )
        second = self.backend.handle(
            {"op": "import_selected", "job_id": queued["id"], "path": "02.flac", "track": tracks[1]}
        )
        self.assertEqual(second["remaining"], 0)
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "imported")
        self.assertEqual(len(self.backend.library.list("music")), 2)
        self.assertEqual(Path(first["path"]).name, "First - Example - Album (2020-07-03).flac")
        self.assertEqual(Path(second["path"]).name, "Second - Example - Album (2020-07-03).flac")

    def test_music_file_selection_is_set_before_torrent_add(self):
        song = {
            "kind": "music",
            "scope": "song",
            "id": "song-1",
            "title": "First",
            "artist": "Example",
            "album": "Album",
            "releaseDate": "2020-07-03",
        }
        self.fake.files = [{"name": "01.flac"}, {"name": "02.flac"}, {"name": "cover.jpg"}]
        inspected = self.backend.handle({"op": "inspect", "url": "magnet:?xt=urn:btih:abc"})
        self.assertEqual([file["audio"] for file in inspected["files"]], [True, True, False])
        self.backend.handle(
            {"op": "queue", "title": song, "url": "magnet:?xt=urn:btih:abc", "selected_files": [1]}
        )
        add = next(values for path, values in self.fake.calls if path == "torrents/add")
        self.assertEqual(add["filePriorities"], "0,1,0")

    def test_scan_moves_unmanaged_movie_with_nfo_and_deletes_related_files(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        source = incoming / "The.General.1926.mkv"
        source.write_bytes(b"video")
        subtitle = incoming / "English.srt"
        subtitle.write_text("subtitle")
        (incoming / "movie.nfo").write_text(
            "<movie><title>The General</title><year>1926</year>"
            '<uniqueid type="imdb">tt0017925</uniqueid></movie>'
        )
        (incoming / "unrelated.txt").write_text("extra")
        result = self.backend.handle({"op": "scan", "kind": "movie", "path": str(incoming)})
        self.assertEqual(len(result["imported"]), 1)
        self.assertFalse(source.exists())
        target = Path(result["imported"][0]["path"])
        self.assertTrue(target.is_file())
        self.assertFalse(subtitle.exists())
        self.assertEqual(target.with_suffix(".srt").read_text(), "subtitle")
        self.assertTrue((target.parent / "movie.nfo").exists())
        self.backend.handle({"op": "delete_local", "path": str(target)})
        self.assertFalse(target.exists())
        self.assertFalse((target.parent / "movie.nfo").exists())
        self.assertFalse(target.parent.exists())

    def test_scan_does_not_guess_unmatched_subtitle_in_multi_video_folder(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        for name in ("First.2024.mkv", "Second.2025.mkv"):
            (incoming / name).write_bytes(b"video")
        subtitle = incoming / "English.srt"
        subtitle.write_text("subtitle")
        titles = {
            "2024": self.movie
            | {"id": "tt-first", "imdbId": "tt-first", "title": "First", "year": 2024},
            "2025": self.movie
            | {"id": "tt-second", "imdbId": "tt-second", "title": "Second", "year": 2025},
        }
        with patch(
            "media.torrent_backend.catalogue_match",
            side_effect=lambda _catalogue, _kind, parsed: titles[str(parsed["year"])],
        ):
            result = self.backend.handle({"op": "scan", "kind": "movie", "path": str(incoming)})
        self.assertEqual(len(result["imported"]), 2)
        self.assertTrue(subtitle.exists())
        self.assertFalse(
            any(Path(row["path"]).with_suffix(".srt").exists() for row in result["imported"])
        )

    def test_default_scans_movies_and_series_separately(self):
        movies = self.root / "Videos/Movies"
        series = self.root / "Videos/Series"
        movies.mkdir(parents=True)
        series.mkdir(parents=True)
        (movies / "movie.mkv").write_bytes(b"movie")
        (series / "show.S01E01.mkv").write_bytes(b"show")
        with patch("media.torrent_backend.catalogue_match", return_value=None):
            movie_result = self.backend.handle({"op": "scan", "kind": "movie"})
            series_result = self.backend.handle({"op": "scan", "kind": "tv"})
        self.assertEqual(
            [Path(item["path"]).name for item in movie_result["review"]], ["movie.mkv"]
        )
        self.assertEqual(
            [Path(item["path"]).name for item in series_result["review"]], ["show.S01E01.mkv"]
        )

    def test_movie_scan_ignores_completed_tv_torrent(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        name = "01E01.The.Crocodiles.Dilemma.mkv"
        (incoming / name).write_bytes(b"video")
        self.fake.files = [{"name": name, "priority": 1}]
        result = self.backend.handle({"op": "scan", "kind": "movie"})
        self.assertEqual(result["review"], [])

    def test_series_guess_uses_parent_title_and_episode_name(self):
        file = Path("Fargo.SEASON.01.S01.COMPLETE.1080p/01E01.The.Crocodiles.Dilemma.mkv")
        parsed = guess(file, "tv")
        self.assertEqual(parsed["title"], "Fargo")
        self.assertEqual((parsed["season"], parsed["episode"]), (1, 1))
        self.assertIn("Crocodiles", parsed["episodeTitle"])

    def test_scan_moves_complete_series_season_as_one_torrent(self):
        show = {"kind": "tv", "id": "tt9", "imdbId": "tt9", "title": "Fargo", "year": 2014}
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        names = [f"Fargo.S01E{episode:02d}.mkv" for episode in (1, 2)]
        for name in names:
            (incoming / name).write_bytes(b"video")
        subtitles = [f"Fargo.S01E{episode:02d}.en.srt" for episode in (1, 2)]
        for name in subtitles:
            (incoming / name).write_text("subtitle")
        self.fake.files = [{"name": name, "priority": 1} for name in names + subtitles]
        with patch("media.torrent_backend.catalogue_match", return_value=show):
            result = self.backend.handle({"op": "scan", "kind": "tv"})
        self.assertEqual(len(result["imported"]), 2)
        self.assertFalse(any((incoming / name).exists() for name in names))
        season = Path(result["imported"][0]["path"]).parent
        self.assertEqual(len(list(season.glob("*.mkv"))), 2)
        self.assertEqual(len(list(season.glob("*.en.srt"))), 2)
        self.assertEqual(len(self.backend.library.files(show)), 2)

    def test_matching_one_episode_imports_its_whole_series_torrent(self):
        show = {"kind": "tv", "id": "tt9", "imdbId": "tt9", "title": "Fargo", "year": 2014}
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        names = [f"Fargo.S01E{episode:02d}.mkv" for episode in (1, 2)]
        for name in names:
            (incoming / name).write_bytes(b"video")
        self.fake.files = [{"name": name, "priority": 1} for name in names]
        with patch("media.torrent_backend.catalogue_match", return_value=None):
            result = self.backend.handle({"op": "scan", "kind": "tv"})
        self.assertEqual(len(result["review"]), 2)
        imported = self.backend.handle(
            {
                "op": "scan_import",
                "token": result["review"][0]["token"],
                "title": show,
                "season": 1,
                "episode": 1,
            }
        )
        self.assertEqual(len(imported["removedTokens"]), 2)
        self.assertEqual(len(self.backend.library.files(show)), 2)
        self.assertFalse(any((incoming / name).exists() for name in names))

    def test_scan_episode_suggestions_use_catalogue_episode_title(self):
        token = "scan-token"
        self.backend.scan_pending[token] = {
            "kind": "tv",
            "guess": {"title": "Fargo", "season": 1, "episode": 1},
        }

        class Catalogue:
            def browse(self, request):
                return {"items": [{"kind": "tv", "id": "tt9", "title": "Fargo", "year": 2014}]}

            def episodes(self, request):
                return {"items": [{"number": 1, "title": "The Crocodile's Dilemma"}], "next": ""}

        with patch("media.backend.Backend", return_value=Catalogue()):
            result = self.backend.handle({"op": "scan_lookup", "token": token, "query": "Fargo"})
        self.assertEqual(result[0]["episodeLabel"], "S01E01 · The Crocodile's Dilemma")

    def test_deleting_episode_removes_whole_season_folder(self):
        show = {"kind": "tv", "id": "tt9", "imdbId": "tt9", "title": "Example", "year": 2020}
        paths = []
        for episode in (1, 2):
            source = self.root / f"Example.S01E{episode:02d}.mkv"
            source.write_bytes(b"video")
            paths.append(self.backend.library.add(show, source))
        season = Path(paths[0]).parent
        (season / "subtitles.srt").write_text("extra")
        result = self.backend.handle({"op": "delete_local", "path": paths[0]})
        self.assertEqual(set(result["removed"]), set(paths))
        self.assertFalse(season.exists())
        self.assertEqual(self.backend.library.files(show), [])

    def test_scan_keeps_uncertain_movie_for_explicit_catalogue_match(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        source = incoming / "The.General.1926.mkv"
        source.write_bytes(b"video")
        with patch("media.torrent_backend.catalogue_match", return_value=None):
            result = self.backend.handle({"op": "scan", "kind": "movie", "path": str(incoming)})
        self.assertEqual(len(result["review"]), 1)
        self.assertTrue(source.exists())
        token = result["review"][0]["token"]
        imported = self.backend.handle({"op": "scan_import", "token": token, "title": self.movie})
        self.assertTrue(Path(imported["path"]).exists())
        self.assertFalse(source.exists())

    def test_scan_existing_qbit_file_moves_seeding_source(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        source = incoming / "The.General.1926.mkv"
        source.write_bytes(b"video")
        subtitle = incoming / "English.srt"
        subtitle.write_text("subtitle")
        self.fake.files = [
            {"name": source.name, "priority": 1},
            {"name": subtitle.name, "priority": 1},
        ]
        (incoming / "movie.nfo").write_text(
            "<movie><title>The General</title><year>1926</year>"
            '<uniqueid type="imdb">tt0017925</uniqueid></movie>'
        )
        result = self.backend.handle({"op": "scan", "kind": "movie", "path": str(incoming)})
        self.assertEqual(len(result["imported"]), 1)
        self.assertFalse(source.exists())
        self.assertFalse(subtitle.exists())
        self.assertTrue(Path(result["imported"][0]["path"]).with_suffix(".srt").exists())
        self.assertTrue(self.backend.library.files(self.movie)[0]["torrent"])

    def test_scan_does_not_overwrite_existing_library_file(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        source = incoming / "The.General.1926.mkv"
        source.write_bytes(b"video")
        self.fake.files = [{"name": source.name, "priority": 1}]
        target = Path(self.backend.library.add(self.movie, source))
        with patch("media.torrent_backend.catalogue_match", return_value=self.movie):
            result = self.backend.handle({"op": "scan", "kind": "movie"})
        self.assertEqual(len(result["imported"]), 0)
        self.assertEqual(len(result["review"]), 1)
        self.assertIn("already exists", result["review"][0]["reason"])
        self.assertTrue(source.exists())
        self.assertTrue(target.is_file())

    def test_torrent_import_does_not_overwrite_library_subtitle(self):
        incoming = self.root / "Incoming"
        incoming.mkdir()
        self.fake.save_path = str(incoming)
        source = incoming / "The.General.1926.mkv"
        subtitle = source.with_suffix(".srt")
        source.write_bytes(b"video")
        subtitle.write_bytes(b"incoming subtitle")
        self.fake.files = [{"name": path.name, "priority": 1} for path in (source, subtitle)]
        target = destination(self.movie, source)
        target.parent.mkdir(parents=True)
        target.with_suffix(".srt").write_bytes(b"existing subtitle")
        with patch("media.torrent_backend.catalogue_match", return_value=self.movie):
            result = self.backend.handle({"op": "scan", "kind": "movie", "path": str(incoming)})
        self.assertEqual(result["imported"], [])
        self.assertIn("subtitle already exists", result["review"][0]["reason"])
        self.assertTrue(source.exists())
        self.assertTrue(subtitle.exists())
        self.assertEqual(target.with_suffix(".srt").read_bytes(), b"existing subtitle")

    def test_deleting_torrent_import_removes_torrent_and_library_link(self):
        self.backend.handle({"op": "queue", "title": self.movie, "url": "magnet:?xt=urn:btih:abc"})
        source = Path(self.fake.save_path) / "The.General.1926.mkv"
        source.write_bytes(b"video" * 250000)
        self.fake.files = [{"name": source.name, "priority": 1}]
        self.backend.handle({"op": "jobs"})
        target = destination(self.movie, source)
        self.assertTrue(self.backend.library.files(self.movie)[0]["torrent"])
        result = self.backend.handle({"op": "delete_local", "path": str(target)})
        self.assertTrue(result["torrent"])
        self.assertFalse(target.exists())
        self.assertEqual(self.backend.library.files(self.movie), [])
        self.assertIn(
            ("torrents/delete", {"hashes": "a" * 40, "deleteFiles": "true"}), self.fake.calls
        )

    def test_delete_job_removes_tracked_download_without_local_file(self):
        queued = self.backend.handle(
            {"op": "queue", "title": self.movie, "url": "magnet:?xt=urn:btih:abc"}
        )
        staging = Path(self.fake.save_path)
        download = staging / "The.General.1926.mkv"
        download.write_bytes(b"video")
        self.fake.files = [{"name": download.name, "priority": 1}]
        with self.backend.db() as db:
            db.execute("UPDATE torrent_jobs SET status='imported' WHERE id=?", (queued["id"],))
        result = self.backend.handle({"op": "delete_job", "job_id": queued["id"]})
        self.assertTrue(result["torrent"])
        self.assertFalse(staging.exists())
        with self.backend.db() as db:
            self.assertIsNone(
                db.execute("SELECT id FROM torrent_jobs WHERE id=?", (queued["id"],)).fetchone()
            )

    def test_book_and_game_destinations(self):
        book = {
            "kind": "book",
            "id": "OL123W",
            "title": "A Book",
            "year": 1901,
            "author": "A Writer",
        }
        game = {"kind": "game", "id": "42", "title": "A Game", "year": 1980}
        self.assertEqual(
            destination(book, Path("source.epub")),
            self.root / "Documents/Books/A Writer/A Book (1901)/A Book (1901).epub",
        )
        self.assertEqual(
            destination(game, Path("source.zip")),
            self.root / "data/zephyrus-shell/games/A Game (1980)/A Game (1980).zip",
        )

    def test_multifile_game_keeps_bundle_names(self):
        game = {"kind": "game", "id": "42", "title": "A Game", "year": 1980}
        queued = self.backend.handle(
            {"op": "queue", "title": game, "url": "magnet:?xt=urn:btih:abc"}
        )
        staging = Path(self.fake.save_path)
        for name in ("disc.bin", "disc.cue"):
            (staging / name).write_bytes(b"content")
        self.fake.files = [{"name": name, "priority": 1} for name in ("disc.bin", "disc.cue")]
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["status"], "imported")
        names = {Path(file["path"]).name for file in self.backend.library.files(game)}
        self.assertEqual(names, {"disc.bin", "disc.cue"})
        self.assertEqual(self.backend.handle({"op": "jobs"})[0]["id"], queued["id"])

    def test_web_api_login_cookie_and_referer(self):
        calls = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                calls.append(
                    (
                        self.path,
                        self.headers.get("Referer"),
                        self.headers.get("Cookie"),
                        body,
                        self.headers.get("Content-Type"),
                    )
                )
                self.send_response(200)
                if self.path.endswith("/auth/login"):
                    self.send_header("Set-Cookie", "SID=test-token; path=/")
                self.end_headers()
                self.wfile.write(b"Ok.")

            def do_GET(self):
                calls.append(
                    (
                        self.path,
                        self.headers.get("Referer"),
                        self.headers.get("Cookie"),
                        "",
                        self.headers.get("Authorization"),
                    )
                )
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"[{" + b'"name":"public","enabled":true' + b"}]")

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            origin = f"http://127.0.0.1:{server.server_port}"
            client = QBitClient({"url": origin, "username": "admin", "password": "secret"})
            self.assertEqual(client.call("search/plugins")[0]["name"], "public")
            client.call(
                "torrents/add", {"urls": "magnet:?xt=urn:btih:abc", "savepath": "/tmp/example"}
            )
            self.assertEqual(
                [item[0] for item in calls],
                ["/api/v2/auth/login", "/api/v2/search/plugins", "/api/v2/torrents/add"],
            )
            self.assertTrue(all(item[1] == origin for item in calls))
            self.assertEqual(calls[1][2], "SID=test-token")
            self.assertIn('name="savepath"\r\n\r\n/tmp/example', calls[2][3])
            self.assertTrue(calls[2][4].startswith("multipart/form-data; boundary="))
            calls.clear()
            anonymous = QBitClient({"url": origin})
            self.assertEqual(anonymous.call("search/plugins")[0]["name"], "public")
            self.assertEqual([item[0] for item in calls], ["/api/v2/search/plugins"])
            calls.clear()
            keyed = QBitClient({"url": origin, "username": "unused", "api_key": "qbt_test"})
            self.assertEqual(keyed.call("search/plugins")[0]["name"], "public")
            self.assertEqual([item[0] for item in calls], ["/api/v2/search/plugins"])
            self.assertEqual(calls[0][4], "Bearer qbt_test")
        finally:
            server.shutdown()
            thread.join(timeout=2)
            server.server_close()

    def test_local_default_needs_no_config_file(self):
        self.assertEqual(self.backend.config(), {"url": "http://127.0.0.1:8080"})

    def test_existing_library_sweep_requires_reviewed_identity(self):
        source = self.root / "Videos/Movies/Loose.mkv"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"video")
        script = Path(__file__).resolve().parents[1] / "scripts/import-local-media.py"
        inventory = subprocess.run(
            ["python3", str(script), "--inventory"], capture_output=True, text=True, check=True
        )
        rows = json.loads(inventory.stdout)
        self.assertEqual(rows[0]["path"], str(source))
        self.assertEqual(rows[0]["id"], "")
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps([rows[0] | self.movie]))
        preview = subprocess.run(
            ["python3", str(script), "--manifest", str(manifest)],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("The General (1926).mkv", preview.stdout)
        self.assertFalse(destination(self.movie, source).exists())
        subprocess.run(
            ["python3", str(script), "--manifest", str(manifest), "--apply"],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertTrue(destination(self.movie, source).exists())
        self.assertFalse(source.exists())


if __name__ == "__main__":
    unittest.main()
