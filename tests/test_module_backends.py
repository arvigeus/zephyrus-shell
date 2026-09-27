import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

from plugins.music import backend as music
from plugins.files import backend as files
from games.igdb import Client
from games.backend import GamesError


class MusicTests(unittest.TestCase):
    def test_artist_selection_does_not_fetch_every_album_tracklist(self):
        calls = []
        def apple(path, params=None):
            calls.append(path)
            if path.endswith('/albums'):
                return {'data': [{'id': str(n), 'type': 'albums', 'attributes': {'name': 'Album ' + str(n)}} for n in range(25)], 'next': '/next'}
            if path.endswith('/view/top-songs'):
                return {'data': []}
            return {'data': [{'id': '123', 'type': 'artists', 'attributes': {'name': 'Artist'}}]}
        with patch.object(music, 'apple_url', side_effect=apple):
            result = music.artist_details({'id': '123', 'source': 'apple'})
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(result['albums']), 25)
        self.assertTrue(result['albumPaging']['hasMore'])
        self.assertFalse(any('/tracks' in path for path in calls))

    def test_more_artist_albums_does_not_load_tracks(self):
        with patch.object(music, 'apple_artist_albums', return_value={'items': [], 'offset': 50, 'hasMore': True}), \
             patch.object(music, 'tracks_for_album', side_effect=AssertionError('Unnecessary track request')):
            self.assertEqual(music.artist_albums_page({'artistId': '123', 'offset': 25})['offset'], 50)

    def test_artist_songs_continue_through_album_tracks_after_top_songs(self):
        album = {'id': '456', 'title': 'Album', 'cover': ''}
        song = {'kind': 'song', 'id': '789', 'title': 'Another song'}
        with patch.object(music, 'apple_artist_song_cursor', return_value={'data': [], 'next': ''}), \
             patch.object(music, 'apple_artist_albums', return_value={'items': [album], 'offset': 1, 'hasMore': False}) as albums, \
             patch.object(music, 'tracks_for_album', return_value=[song]):
            top = music.artist_songs_page({'artistId': '123', 'cursor': '/v1/catalog/us/artists/123/view/top-songs?offset=25'})
            self.assertTrue(top['hasMore'])
            page = music.artist_songs_page({'artistId': '123', 'albumOffset': 0})
        self.assertEqual(page['items'], [song])
        self.assertFalse(page['hasMore'])
        albums.assert_called_once_with('123', offset=0, limit=2)

    def test_artist_song_cursor_rejects_other_hosts_and_artists(self):
        with patch.object(music, 'music_config', return_value={'storefront': 'us'}):
            for cursor in ('https://other.example/v1/catalog/us/artists/123/view/top-songs',
                           '/v1/catalog/us/artists/999/view/top-songs'):
                with self.assertRaises(music.MusicError):
                    music.apple_artist_song_cursor('123', cursor)


class FileTests(unittest.TestCase):
    def test_removal_uses_trash_and_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / 'home'; home.mkdir()
            target = Path(root) / 'outside'; target.write_text('keep')
            link = home / 'link'; link.symlink_to(target)
            with patch.object(files, 'HOME', home), patch.object(files.shutil, 'which', return_value='/usr/bin/gio'), \
                 patch.object(files.subprocess, 'run', return_value=Mock(returncode=0)) as run:
                result = files.delete_entry(str(link))
            self.assertEqual(run.call_args.args[0], ['/usr/bin/gio', 'trash', '--', str(link)])
            self.assertTrue(target.exists())
            self.assertIn('Trash', result['message'])

    def test_home_and_parent_paths_cannot_be_removed(self):
        with tempfile.TemporaryDirectory() as root, patch.object(files, 'HOME', Path(root)):
            with self.assertRaises(ValueError): files.delete_entry(root)
            with self.assertRaises(ValueError): files.delete_entry(root + '/child/..')


class IGDBTests(unittest.TestCase):
    def test_expired_token_refreshes_once_without_exposing_credentials(self):
        tokens, requests = [], []
        def request(url, method, headers, body, *args):
            if 'oauth2/token' in url:
                tokens.append(1)
                self.assertNotIn('secret', url)
                return {'access_token': 'token' + str(len(tokens)), 'expires_in': 3600}
            requests.append(headers['Authorization'])
            if len(requests) == 1:
                raise GamesError('Provider request failed (HTTP 401).')
            return [{'id': 1}]
        client = Client(lambda: {'igdb_client_id': 'id', 'igdb_client_secret': 'secret'}, request, GamesError)
        with patch('games.igdb.time.sleep'):
            self.assertEqual(client.query('games', 'fields name;'), [{'id': 1}])
        self.assertEqual(requests, ['Bearer token1', 'Bearer token2'])
        self.assertEqual(len(tokens), 2)

    def test_literal_search_does_not_add_apicalypse_clauses(self):
        client = Client(lambda: {}, Mock())
        client.query = Mock(return_value=[])
        query = 'test"; where id > 0; search "'
        client.browse(query, {'ordering': '-added'}, 50, 50)
        body = client.query.call_args.args[1]
        self.assertIn('search ' + json.dumps(query) + ';', body)
        self.assertIn('offset 50;', body)
