import json
import os
import shutil
import tempfile
import unittest
import wave
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from unittest.mock import Mock, patch

from games.backend import GamesError
from games.igdb import Client
from plugins.files import backend as files
from plugins.music import backend as music


class MusicTests(unittest.TestCase):
    def test_download_capabilities_are_independent(self):
        cases = (
            ({}, {"track": False, "album": False}),
            ({"track": "https://example.test/tracks/{id}"}, {"track": True, "album": False}),
            ({"album": "https://example.test/albums/{id}"}, {"track": False, "album": True}),
            (
                {
                    "track": "https://example.test/tracks/{id}",
                    "album": "https://example.test/albums/{id}",
                },
                {"track": True, "album": True},
            ),
        )
        for download, expected in cases:
            with (
                self.subTest(download=download),
                patch.object(
                    music, "music_config", return_value={"providers": [{"download": download}]}
                ),
            ):
                self.assertEqual(music.download_capabilities(), expected)

        with patch.object(
            music,
            "music_config",
            return_value={
                "providers": [
                    {
                        "search_url": "https://example.test/search",
                        "stream_url": "https://example.test/{id}",
                        "download": {"track": "stream"},
                    },
                    {
                        "search_url": "https://example.test/search",
                        "stream_url": "https://example.test/{id}",
                        "download": {"album": "stream"},
                    },
                ]
            },
        ):
            self.assertEqual(music.download_capabilities(), {"track": True, "album": True})
            self.assertEqual(music.download_provider("album")["download"], {"album": "stream"})

    def test_download_templates_expand_catalog_metadata(self):
        provider = {
            "base_url": "https://example.test",
            "download": {
                "track": "{base_url}/tracks/{id}?artist={artist}&title={title}&isrc={isrc}",
                "album": "{base_url}/albums/{album_id}?name={title}",
            },
        }
        with patch.object(music, "music_config", return_value={"providers": [provider]}):
            self.assertEqual(
                music.download_url(
                    "track",
                    {"id": "song/42", "title": "Blue & Gold", "artist": "A/B", "isrc": "US123"},
                ),
                "https://example.test/tracks/song%2F42?artist=A%2FB&title=Blue%20%26%20Gold&isrc=US123",
            )
            self.assertEqual(
                music.download_url("album", {"id": "album 7", "title": "Blue & Gold"}),
                "https://example.test/albums/album%207?name=Blue%20%26%20Gold",
            )

    def test_download_template_errors_do_not_expose_url(self):
        for template, item in (
            ("https://example.test/{isrc}", {"id": "1", "title": "Song"}),
            ("https://example.test/{unexpected}", {"id": "1"}),
            ("file:///tmp/{id}", {"id": "1"}),
            ("https://example.test:bad/{id}", {"id": "1"}),
        ):
            with (
                self.subTest(template=template),
                patch.object(
                    music,
                    "music_config",
                    return_value={"providers": [{"download": {"track": template}}]},
                ),
            ):
                with self.assertRaises(music.MusicError) as error:
                    music.download_url("track", item)
                self.assertNotIn("example.test", str(error.exception))

        with patch.object(
            music,
            "music_config",
            return_value={"providers": [{"download": {"album": "https://example.test/{id}"}}]},
        ):
            with self.assertRaisesRegex(music.MusicError, "missing"):
                music.download_url("album", {"id": "name:unknown album", "title": "Unknown Album"})

    def test_existing_provider_config_remains_valid(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "zephyrus-shell" / "music.json"
            path.parent.mkdir()
            path.write_text(
                json.dumps(
                    {
                        "providers": [
                            {
                                "search_url": "https://example.test/search",
                                "stream_url": "https://example.test/{id}",
                            }
                        ]
                    }
                )
            )
            with (
                patch.dict("os.environ", {"XDG_CONFIG_HOME": root}),
                patch.object(music, "_music_config", None),
            ):
                self.assertEqual(music.download_capabilities(), {"track": False, "album": False})

    def test_stream_download_requires_search_and_stream_templates(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "zephyrus-shell" / "music.json"
            path.parent.mkdir()
            path.write_text(json.dumps({"providers": [{"download": {"track": "stream"}}]}))
            with (
                patch.dict(os.environ, {"XDG_CONFIG_HOME": root}),
                patch.object(music, "_music_config", None),
            ):
                with self.assertRaisesRegex(music.MusicError, "search_url and stream_url"):
                    music.music_config()

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is needed for the stream save test")
    def test_stream_download_copies_audio_to_music(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source.wav"
            with wave.open(str(source), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(8000)
                audio.writeframes(b"\0\0" * 800)
            destination = Path(root) / "Music"

            class QuietHandler(SimpleHTTPRequestHandler):
                def do_GET(self):
                    if self.headers.get("X-Music-Test") != "ok":
                        self.send_error(403)
                        return
                    super().do_GET()

                def log_message(self, *args):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=root))
            thread = Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)
            provider = {"download": {"track": "stream"}, "headers": {"X-Music-Test": "ok"}}
            song = {
                "kind": "song",
                "id": "42",
                "artist": "A/B",
                "title": "Blue & Gold",
                "album": "Test Album",
                "releaseDate": "2020-07-03",
            }
            with (
                patch.object(music, "download_provider", return_value=provider),
                patch.object(
                    music,
                    "resolve_track",
                    return_value={
                        "url": f"http://127.0.0.1:{server.server_port}/source.wav",
                        "headers": {},
                    },
                ) as resolve,
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(destination)}),
            ):
                result = music.open_download({"kind": "track", "item": song})
                second = music.open_download({"kind": "track", "item": song})
            self.assertEqual(result["saved"], 1)
            self.assertEqual(second["saved"], 1)
            self.assertEqual(
                Path(result["path"]).name, "Blue & Gold - A B - Test Album (2020-07-03).mka"
            )
            self.assertEqual(
                Path(second["path"]).name, "Blue & Gold - A B - Test Album (2020-07-03) (2).mka"
            )
            self.assertEqual(Path(result["path"]).parent, destination)
            self.assertGreater(Path(result["path"]).stat().st_size, 0)
            self.assertEqual(list(destination.glob(".zephyrus-music-*")), [])
            self.assertEqual(
                resolve.call_args.kwargs, {"providers": [provider], "local_first": False}
            )

    def test_stream_download_needs_full_release_date(self):
        provider = {"download": {"track": "stream"}}
        song = {
            "kind": "song",
            "id": "42",
            "title": "Blue & Gold",
            "artist": "A/B",
            "album": "Test Album",
            "releaseDate": "2020",
        }
        with patch.object(music, "resolve_track") as resolve:
            with self.assertRaisesRegex(music.MusicError, "full release date"):
                music.save_stream_track(song, provider, Path("/unused"))
        resolve.assert_not_called()

    def test_album_stream_download_reports_partial_results(self):
        provider = {"download": {"album": "stream"}}
        tracks = [{"id": "1", "title": "First"}, {"id": "2", "title": "Second"}]
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(
                music,
                "album_details",
                return_value={
                    "album": {"id": "7", "artist": "Artist", "title": "Album"},
                    "songs": tracks,
                },
            ),
            patch.object(music, "tracks_for_album", return_value=tracks) as pages,
            patch.object(
                music,
                "save_stream_track",
                side_effect=["/tmp/first.mka", music.MusicError("Failed")],
            ) as save,
            patch.dict(os.environ, {"XDG_MUSIC_DIR": str(Path(root) / "Music")}),
        ):
            result = music.save_stream_download("album", {"id": "7"}, provider)
        self.assertEqual((result["saved"], result["failed"]), (1, 1))
        self.assertEqual(result["path"], str(Path(root) / "Music"))
        self.assertEqual([call.args[2] for call in save.call_args_list], [Path(root) / "Music"] * 2)
        pages.assert_called_once_with(
            {"id": "7", "artist": "Artist", "title": "Album"}, all_pages=True
        )

    def test_album_download_reads_later_track_pages(self):
        def page(path, params):
            self.assertEqual(path, "/albums/7/tracks")
            if params["offset"] == 0:
                return {
                    "data": [{"id": "1", "attributes": {"name": "First", "artistName": "Artist"}}],
                    "next": "/more",
                }
            return {"data": [{"id": "2", "attributes": {"name": "Second", "artistName": "Artist"}}]}

        with patch.object(music, "apple_url", side_effect=page) as request:
            self.assertEqual(len(music.tracks_for_album({"id": "7"}, all_pages=True)), 2)
        self.assertEqual(request.call_count, 2)

    def test_download_open_failure_uses_music_error(self):
        with (
            patch.object(
                music,
                "music_config",
                return_value={"providers": [{"download": {"album": "https://example.test/{id}"}}]},
            ),
            patch.object(
                music, "browser_argv", return_value=["missing-browser", "https://example.test/7"]
            ) as argv,
            patch.object(music.subprocess, "Popen", side_effect=OSError("missing")),
        ):
            with self.assertRaisesRegex(music.MusicError, "Could not open"):
                music.open_download({"kind": "album", "item": {"id": "7"}})
            argv.assert_called_once_with("music", "https://example.test/7")

    def test_artist_selection_does_not_fetch_every_album_tracklist(self):
        calls = []

        def apple(path, params=None):
            calls.append(path)
            if path.endswith("/albums"):
                return {
                    "data": [
                        {"id": str(n), "type": "albums", "attributes": {"name": "Album " + str(n)}}
                        for n in range(25)
                    ],
                    "next": "/next",
                }
            if path.endswith("/view/top-songs"):
                return {"data": []}
            return {"data": [{"id": "123", "type": "artists", "attributes": {"name": "Artist"}}]}

        with patch.object(music, "apple_url", side_effect=apple):
            result = music.artist_details({"id": "123", "source": "apple"})
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(result["albums"]), 25)
        self.assertTrue(result["albumPaging"]["hasMore"])
        self.assertFalse(any("/tracks" in path for path in calls))

    def test_more_artist_albums_does_not_load_tracks(self):
        with (
            patch.object(
                music,
                "apple_artist_albums",
                return_value={"items": [], "offset": 50, "hasMore": True},
            ),
            patch.object(
                music, "tracks_for_album", side_effect=AssertionError("Unnecessary track request")
            ),
        ):
            self.assertEqual(
                music.artist_albums_page({"artistId": "123", "offset": 25})["offset"], 50
            )

    def test_artist_songs_continue_through_album_tracks_after_top_songs(self):
        album = {"id": "456", "title": "Album", "cover": ""}
        song = {"kind": "song", "id": "789", "title": "Another song"}
        with (
            patch.object(music, "apple_artist_song_cursor", return_value={"data": [], "next": ""}),
            patch.object(
                music,
                "apple_artist_albums",
                return_value={"items": [album], "offset": 1, "hasMore": False},
            ) as albums,
            patch.object(music, "tracks_for_album", return_value=[song]),
        ):
            top = music.artist_songs_page(
                {"artistId": "123", "cursor": "/v1/catalog/us/artists/123/view/top-songs?offset=25"}
            )
            self.assertTrue(top["hasMore"])
            page = music.artist_songs_page({"artistId": "123", "albumOffset": 0})
        self.assertEqual(page["items"], [song])
        self.assertFalse(page["hasMore"])
        albums.assert_called_once_with("123", offset=0, limit=2)

    def test_artist_song_cursor_rejects_other_hosts_and_artists(self):
        with patch.object(music, "music_config", return_value={"storefront": "us"}):
            for cursor in (
                "https://other.example/v1/catalog/us/artists/123/view/top-songs",
                "/v1/catalog/us/artists/999/view/top-songs",
            ):
                with self.assertRaises(music.MusicError):
                    music.apple_artist_song_cursor("123", cursor)


class FileTests(unittest.TestCase):
    def test_listing_preserves_sorting_and_symlink_home_boundary(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / "home"
            home.mkdir()
            folder = home / "folder"
            folder.mkdir()
            (home / "A.txt").write_text("abc")
            (home / ".hidden").touch()
            (home / "inside").symlink_to(folder)
            (home / "outside").symlink_to(root)
            (home / "broken").symlink_to(home / "missing")
            with patch.object(files, "HOME", home):
                entries = files.list_directory(home)["entries"]
                by_name = {entry["name"]: entry for entry in entries}
                self.assertTrue(by_name["inside"]["is_dir"])
                self.assertFalse(by_name["outside"]["is_dir"])
                self.assertNotIn("broken", by_name)
                self.assertTrue(by_name[".hidden"]["hidden"])
                self.assertEqual(by_name["A.txt"]["size_label"], "3 B")
                self.assertEqual([entry["name"] for entry in entries[:2]], ["folder", "inside"])
                with self.assertRaises(ValueError):
                    files.list_directory(home / "outside")

    def test_removal_uses_trash_and_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / "home"
            home.mkdir()
            target = Path(root) / "outside"
            target.write_text("keep")
            link = home / "link"
            link.symlink_to(target)
            with (
                patch.object(files, "HOME", home),
                patch.object(files.shutil, "which", return_value="/usr/bin/gio"),
                patch.object(files.subprocess, "run", return_value=Mock(returncode=0)) as run,
            ):
                result = files.delete_entry(str(link))
            self.assertEqual(run.call_args.args[0], ["/usr/bin/gio", "trash", "--", str(link)])
            self.assertTrue(target.exists())
            self.assertIn("Trash", result["message"])

    def test_home_and_parent_paths_cannot_be_removed(self):
        with tempfile.TemporaryDirectory() as root, patch.object(files, "HOME", Path(root)):
            with self.assertRaises(ValueError):
                files.delete_entry(root)
            with self.assertRaises(ValueError):
                files.delete_entry(root + "/child/..")


class IGDBTests(unittest.TestCase):
    def test_expired_token_refreshes_once_without_exposing_credentials(self):
        tokens, requests = [], []

        def request(url, method, headers, body, *args):
            if "oauth2/token" in url:
                tokens.append(1)
                self.assertNotIn("secret", url)
                return {"access_token": "token" + str(len(tokens)), "expires_in": 3600}
            requests.append(headers["Authorization"])
            if len(requests) == 1:
                raise GamesError("Provider request failed (HTTP 401).")
            return [{"id": 1}]

        client = Client(
            lambda: {"igdb_client_id": "id", "igdb_client_secret": "secret"}, request, GamesError
        )
        with patch("games.igdb.time.sleep"):
            self.assertEqual(client.query("games", "fields name;"), [{"id": 1}])
        self.assertEqual(requests, ["Bearer token1", "Bearer token2"])
        self.assertEqual(len(tokens), 2)

    def test_literal_search_does_not_add_apicalypse_clauses(self):
        client = Client(lambda: {}, Mock())
        client.query = Mock(return_value=[])
        query = 'test"; where id > 0; search "'
        client.browse(query, {"ordering": "-added"}, 50, 50)
        body = client.query.call_args.args[1]
        self.assertIn("search " + json.dumps(query) + ";", body)
        self.assertIn("offset 50;", body)
