import json
import unittest
from unittest.mock import Mock, patch

from modules.games.backend import GamesError
from modules.games.igdb import Client


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
        with patch("modules.games.igdb.time.sleep"):
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
