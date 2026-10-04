import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from games import backend as games

FIXTURES = Path(__file__).parent / "fixtures/games"


class GamesParsingTests(unittest.TestCase):
    def test_libraryfolders_reads_both_steam_vdf_shapes(self):
        parsed = games.parse_vdf((FIXTURES / "libraryfolders.vdf").read_text())
        folders = parsed["libraryfolders"]
        self.assertEqual(folders["0"]["path"], "/steam/default")
        self.assertEqual(folders["1"]["path"], "/games/library with spaces")
        self.assertEqual(folders["0"]["apps"]["480"], "1024")

    def test_vdf_quoted_escapes_and_comments(self):
        parsed = games.parse_vdf('/* head */ "root" { "path" "a\\"b" // tail\n }')
        self.assertEqual(parsed["root"]["path"], 'a"b')

    def test_steam_manifest_requires_installed_flag_and_existing_directory(self):
        with tempfile.TemporaryDirectory() as root:
            library = Path(root)
            install = library / "steamapps/common/Sample Game"
            install.mkdir(parents=True)
            raw = games.parse_vdf((FIXTURES / "appmanifest_12345.acf").read_text())
            manifest = games.steam_manifest(raw, library, FIXTURES / "appmanifest_12345.acf")
            self.assertEqual(manifest["externalId"], "12345")
            self.assertTrue(manifest["installed"])
            raw["AppState"]["StateFlags"] = "2"
            self.assertIsNone(
                games.steam_manifest(raw, library, FIXTURES / "appmanifest_12345.acf")
            )

    def test_steam_manifest_does_not_report_missing_install_path(self):
        raw = games.parse_vdf((FIXTURES / "appmanifest_12345.acf").read_text())
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(games.steam_manifest(raw, root, FIXTURES / "appmanifest_12345.acf"))

    def test_steam_owned_game_parser_requires_a_games_list_and_keeps_names(self):
        response = {
            "response": {
                "games": [
                    {"appid": 123, "name": "Example Game"},
                    {"appid": 123, "name": "Duplicate"},
                    {"appid": "bad", "name": "Invalid ID"},
                    {"appid": 456, "name": ""},
                ]
            }
        }
        self.assertEqual(
            games.parse_steam_owned_games(response),
            [
                {
                    "store": "steam",
                    "externalId": "123",
                    "title": "Example Game",
                    "installed": False,
                    "launchable": False,
                }
            ],
        )
        self.assertEqual(games.parse_steam_owned_games({"response": {"games": []}}), [])
        self.assertIsNone(games.parse_steam_owned_games({"response": {}}))

    def test_legendary_parses_owned_json_and_filters_non_records(self):
        raw = json.loads((FIXTURES / "legendary-owned.json").read_text())
        owned = games.parse_legendary_owned(raw)
        self.assertEqual(
            [game["externalId"] for game in owned], ["Catnip", "Anemone", "UnrealEngine"]
        )
        self.assertEqual(owned[0]["title"], "Borderlands 3")

    def test_legendary_installed_requires_real_path_and_keeps_app_name(self):
        with tempfile.TemporaryDirectory() as root:
            install = Path(root) / "Borderlands 3"
            install.mkdir()
            raw = json.loads(
                (FIXTURES / "legendary-installed.json")
                .read_text()
                .replace("__INSTALL_PATH__", str(install))
                .replace("__MISSING_PATH__", str(Path(root) / "missing"))
            )
            installed = games.parse_legendary_installed(raw)
            self.assertEqual(len(installed), 1)
            self.assertEqual(installed[0]["externalId"], "Catnip")
            self.assertEqual(installed[0]["installPath"], str(install))

    def test_legendary_drops_ids_that_could_become_cli_options(self):
        self.assertEqual(
            games.parse_legendary_owned(
                [
                    {"app_name": "Valid-Game_1", "app_title": "Valid Game"},
                    {"app_name": "--help", "app_title": "Invalid Game"},
                    {"app_name": "name with spaces", "app_title": "Invalid Game"},
                ]
            ),
            [
                {
                    "store": "epic",
                    "externalId": "Valid-Game_1",
                    "title": "Valid Game",
                    "installed": False,
                }
            ],
        )


class GamesIdentityTests(unittest.TestCase):
    def test_exact_ids_override_titles_and_edition_tokens_are_retained(self):
        game = {
            "title": "Example Game",
            "storeReferences": [{"store": "steam", "externalId": "123"}],
        }
        items = [
            {"store": "steam", "externalId": "555", "title": "Example Game", "installed": True},
            {"store": "steam", "externalId": "123", "title": "Another Name", "installed": True},
        ]
        match, source = games.match_library_item(game, "steam", items)
        self.assertEqual(match["externalId"], "123")
        self.assertEqual(source, "store-id")
        game["storeReferences"] = []
        self.assertIsNone(
            games.match_library_item({"title": "Example Game Deluxe Edition"}, "steam", items)[0]
        )

    def test_known_store_id_does_not_fall_back_to_a_title_collision(self):
        game = {
            "title": "Example Game",
            "storeReferences": [{"store": "steam", "externalId": "123"}],
        }
        items = [{"externalId": "456", "title": "Example Game", "installed": True}]
        match, source = games.match_library_item(game, "steam", items)
        self.assertIsNone(match)
        self.assertEqual(source, "")

    def test_duplicate_exact_titles_are_ambiguous(self):
        items = [
            {"externalId": "a", "title": "The Example Game", "installed": True},
            {"externalId": "b", "title": "The Example Game", "installed": True},
        ]
        match, source = games.match_library_item({"title": "The Example Game"}, "epic", items)
        self.assertIsNone(match)
        self.assertEqual(source, "")

    def test_manual_override_is_first_exact_match(self):
        game = {
            "title": "Example Game",
            "storeReferences": [{"store": "epic", "externalId": "wrong"}],
        }
        items = [{"externalId": "right", "title": "Different", "installed": True}]
        match, source = games.match_library_item(game, "epic", items, override="right")
        self.assertEqual(match["externalId"], "right")
        self.assertEqual(source, "override")

    def test_unmatched_manual_override_does_not_fall_back_to_catalog_or_title(self):
        game = {
            "title": "Example Game",
            "storeReferences": [{"store": "steam", "externalId": "123"}],
        }
        items = [{"externalId": "123", "title": "Example Game", "installed": True}]
        match, source = games.match_library_item(game, "steam", items, override="456")
        self.assertIsNone(match)
        self.assertEqual(source, "")

    def test_protondb_requires_numeric_steam_identity(self):
        self.assertEqual(games.protondb_url("730"), "https://www.protondb.com/app/730")
        self.assertEqual(games.protondb_url("730/../../bad"), "")
        self.assertEqual(games.protondb_url("0"), "")
        self.assertEqual(games.protondb_url("12345678901"), "")

    def test_external_store_urls_are_host_validated(self):
        self.assertEqual(
            games._safe_store_url("https://evil.invalid/game", "steam", "123"),
            "https://store.steampowered.com/app/123/",
        )
        self.assertEqual(
            games._safe_store_url("https://store.epicgames.com/p/example", "epic", "code"),
            "https://store.epicgames.com/p/example",
        )
        self.assertEqual(
            games._safe_store_url(
                "https://store.steampowered.com@evil.invalid/app/123", "steam", "123"
            ),
            "https://store.steampowered.com/app/123/",
        )
        self.assertEqual(
            games._safe_store_url("https://store.epicgames.com:bad/p/example", "epic", "code"), ""
        )

    def test_igdb_normalizes_provider_data_and_only_accepts_store_product_urls(self):
        raw = {
            "id": 3498,
            "name": "Grand Theft Auto V",
            "summary": "A detailed game.",
            "cover": {"image_id": "co123"},
            "screenshots": [{"image_id": "sc123"}],
            "genres": [{"name": "Action"}],
            "platforms": [{"name": "PC"}],
            "involved_companies": [{"developer": True, "company": {"name": "Rockstar North"}}],
            "websites": [
                {"url": "https://store.steampowered.com/app/271590/"},
                {"url": "https://store.epicgames.com/p/game"},
                {"url": "https://www.epicgames.com/store/en-US/product/another-game/home"},
                {"url": "https://evil.invalid/app/888"},
                {"type": 1, "url": "https://www.rockstargames.com/gta-v"},
            ],
        }
        result = games.normalize_igdb_game(raw, "local-stable-id")
        self.assertEqual(result["id"], "local-stable-id")
        self.assertEqual(result["catalogProvider"], "igdb")
        self.assertEqual(result["catalogProviderId"], "3498")
        self.assertEqual(result["title"], "Grand Theft Auto V")
        self.assertEqual(result["platforms"], ["PC"])
        self.assertEqual(result["officialWebsite"], "https://www.rockstargames.com/gta-v")
        self.assertEqual(result["developers"], ["Rockstar North"])
        self.assertEqual(
            result["storeReferences"],
            [
                {
                    "store": "steam",
                    "externalId": "271590",
                    "url": "https://store.steampowered.com/app/271590/",
                },
                {
                    "store": "epic",
                    "externalId": "game",
                    "url": "https://store.epicgames.com/p/game",
                },
                {
                    "store": "epic",
                    "externalId": "another-game",
                    "url": "https://www.epicgames.com/store/en-US/product/another-game/home",
                },
            ],
        )
        self.assertIn("images.igdb.com", result["cover"]["url"])

    def test_igdb_official_website_accepts_http_but_rejects_unsafe_urls(self):
        websites = [
            {"type": 1, "url": "javascript:alert(1)"},
            {"type": 1, "url": "https://example.com@evil.invalid/"},
            {"type": 1, "url": "https://[broken"},
            {"type": 13, "url": "https://store.steampowered.com/app/123/"},
            {"type": 1, "url": "http://example.org/game"},
        ]
        self.assertEqual(
            games.normalize_igdb_game({"id": 1, "name": "Example", "websites": websites})[
                "officialWebsite"
            ],
            "http://example.org/game",
        )
        self.assertEqual(
            games.normalize_igdb_game({"id": 1, "name": "Example", "websites": websites[:4]})[
                "officialWebsite"
            ],
            "",
        )

    def test_igdb_rejects_invalid_catalog_ids_and_image_ids(self):
        with self.assertRaises(ValueError):
            games.normalize_igdb_game({"id": "--bad", "name": "Example"}, "id")
        result = games.normalize_igdb_game(
            {"id": 4, "name": "Example", "cover": {"image_id": "../bad"}}, "id"
        )
        self.assertIsNone(result["cover"])

    def test_browse_filter_values_are_validated_and_mapped_to_provider_parameters(self):
        backend = object.__new__(games.GamesBackend)
        self.assertEqual(backend._browse_filters({}), {"ordering": "-added"})
        self.assertEqual(backend._browse_filters({"sort": "-updated"}), {"ordering": "-updated"})
        result = backend._browse_filters(
            {
                "genre": "4",
                "platform": 1,
                "sort": "-rating",
                "fromYear": "2010",
                "toYear": "2015",
            }
        )
        self.assertEqual(result["genres"], "4")
        self.assertEqual(result["platforms"], "1")
        self.assertEqual(result["ordering"], "-rating")
        self.assertEqual(result["dates"], "2010-01-01,2015-12-31")
        with self.assertRaisesRegex(games.GamesError, "valid genre or platform"):
            backend._browse_filters({"genre": "4&ordering=name"})
        with self.assertRaisesRegex(games.GamesError, "valid sort order"):
            backend._browse_filters({"sort": "id"})
        with self.assertRaisesRegex(games.GamesError, "start year"):
            backend._browse_filters({"fromYear": "2020", "toYear": "2019"})


class GamesStateTests(unittest.TestCase):
    def test_store_actions_keep_ownership_installation_and_launch_separate(self):
        game = {"title": "Example", "storeReferences": [{"store": "steam", "externalId": "123"}]}
        steam = {
            "available": True,
            "ownershipKnown": True,
            "ownedIds": [],
            "items": [
                {
                    "store": "steam",
                    "externalId": "123",
                    "title": "Example",
                    "installed": True,
                    "launchable": True,
                }
            ],
        }
        row = games.derive_store_state(game, {"steam": steam})[0]
        self.assertEqual(row["ownership"], "not-owned")
        self.assertEqual(row["installation"], "installed")
        self.assertEqual(row["actions"][0]["type"], "play")
        self.assertEqual(row["primaryAction"]["type"], "play")
        self.assertEqual(row["actions"][1]["type"], "uninstall")

    def test_owned_steam_game_not_installed_gets_install_action(self):
        game = {"title": "Example", "storeReferences": [{"store": "steam", "externalId": "123"}]}
        steam = {"available": True, "ownershipKnown": True, "ownedIds": ["123"], "items": []}
        row = games.derive_store_state(game, {"steam": steam})[0]
        self.assertEqual(row["ownership"], "owned")
        self.assertEqual(row["installation"], "not-installed")
        self.assertEqual(row["actions"][0]["type"], "install")
        self.assertEqual(row["primaryAction"]["label"], "Install")

    def test_store_actions_expose_purchase_and_link_states(self):
        steam = {"available": True, "ownershipKnown": True, "ownedIds": [], "items": []}
        linked = {"title": "Example", "storeReferences": [{"store": "steam", "externalId": "123"}]}
        row = games.derive_store_state(linked, {"steam": steam})[0]
        self.assertEqual(row["primaryAction"]["label"], "Buy")
        self.assertEqual(row["primaryAction"]["url"], "https://store.steampowered.com/app/123/")
        self.assertTrue(row["primaryAction"]["enabled"])
        unlinked = games.derive_store_state(
            {"title": "Example", "storeReferences": []}, {"steam": steam}
        )[0]
        self.assertEqual(unlinked["primaryAction"]["label"], "Link")
        self.assertTrue(unlinked["primaryAction"]["enabled"])

    def test_owned_steam_game_can_match_by_unique_title_without_catalog_store_links(self):
        game = {"title": "Example Game", "storeReferences": []}
        steam = {
            "available": True,
            "ownershipKnown": True,
            "ownedIds": ["123"],
            "items": [
                {
                    "store": "steam",
                    "externalId": "123",
                    "title": "Example Game",
                    "installed": False,
                    "launchable": False,
                },
            ],
        }
        row = games.derive_store_state(game, {"steam": steam})[0]
        self.assertEqual(row["ownership"], "owned")
        self.assertEqual(row["installation"], "not-installed")
        self.assertEqual(row["actions"][0]["id"], "steam:install:123")

    def test_epic_matches_legendary_app_name_by_unique_exact_title(self):
        game = {
            "title": "Borderlands 3",
            "storeReferences": [{"store": "epic", "externalId": "epic-offer-id"}],
        }
        epic = {
            "available": True,
            "ownershipKnown": True,
            "installationKnown": True,
            "ownedIds": ["Catnip"],
            "items": [
                {
                    "store": "epic",
                    "externalId": "Catnip",
                    "title": "Borderlands 3",
                    "installed": False,
                }
            ],
        }
        row = games.derive_store_state(game, {"epic": epic})[1]
        self.assertEqual(row["ownership"], "owned")
        self.assertEqual(row["actions"][0]["id"], "epic:install:Catnip")

    def test_epic_unknown_install_state_does_not_offer_install(self):
        game = {
            "title": "Borderlands 3",
            "storeReferences": [{"store": "epic", "externalId": "Catnip"}],
        }
        epic = {
            "available": True,
            "ownershipKnown": True,
            "installationKnown": False,
            "ownedIds": ["Catnip"],
            "items": [{"externalId": "Catnip", "title": "Borderlands 3"}],
        }
        row = games.derive_store_state(game, {"epic": epic})[1]
        self.assertEqual(row["installation"], "unknown")
        self.assertEqual(row["actions"], [])
        self.assertFalse(row["primaryAction"]["enabled"])

    def test_private_steam_profile_never_claims_not_owned(self):
        game = {"title": "Example", "storeReferences": [{"store": "steam", "externalId": "123"}]}
        steam = {
            "available": True,
            "ownershipKnown": False,
            "ownershipConfigured": True,
            "ownedIds": [],
            "items": [],
        }
        row = games.derive_store_state(game, {"steam": steam})[0]
        self.assertEqual(row["ownership"], "unknown")
        self.assertEqual(row["ownershipLabel"], "Steam profile is private or unavailable")
        self.assertEqual(row["actions"], [])

    def test_missing_store_tools_do_not_claim_installation_is_known(self):
        game = {
            "title": "Example",
            "storeReferences": [
                {"store": "steam", "externalId": "123"},
                {"store": "epic", "externalId": "Catnip"},
            ],
        }
        unavailable = {
            "steam": {
                "available": False,
                "installationKnown": False,
                "ownershipKnown": False,
                "items": [],
                "ownedIds": [],
            },
            "epic": {
                "available": False,
                "installationKnown": False,
                "ownershipKnown": False,
                "items": [],
                "ownedIds": [],
            },
        }
        steam, epic = games.derive_store_state(game, unavailable)
        self.assertEqual(steam["installation"], "unknown")
        self.assertEqual(epic["installation"], "unknown")
        self.assertEqual(steam["actions"], [])
        self.assertEqual(epic["actions"], [])

    def test_steam_can_offer_install_when_the_client_exists_but_library_scan_is_empty(self):
        game = {"title": "Example", "storeReferences": [{"store": "steam", "externalId": "123"}]}
        steam = {
            "available": True,
            "installationKnown": False,
            "ownershipKnown": True,
            "ownedIds": ["123"],
            "items": [],
        }
        row = games.derive_store_state(game, {"steam": steam})[0]
        self.assertEqual(row["installation"], "unknown")
        self.assertEqual(row["actions"][0]["type"], "install")


class GamesBackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = self.root / "config/games.json"
        self.config.parent.mkdir(parents=True)
        self.config.write_text(
            json.dumps(
                {
                    "igdb_client_id": "",
                    "igdb_client_secret": "",
                    "steam_api_key": "",
                    "steam_id": "",
                }
            )
        )
        self.calls = []
        self.backend = games.GamesBackend(
            config=self.config,
            data=self.root / "data",
            env={"HOME": str(self.root), "XDG_DATA_HOME": str(self.root / "xdg-data"), "PATH": ""},
            request=self.fake_request,
            popen=Mock(),
        )

    def tearDown(self):
        self.temp.cleanup()

    def fake_request(self, url, method="GET", headers=None, body=None, timeout=15, max_bytes=1000):
        self.calls.append((url, method, headers, body))
        if "protondb.com/api/v1/reports/summaries/" in url:
            return {"tier": "gold", "trendingTier": "platinum", "total": 42, "confidence": "strong"}
        raise AssertionError("Unexpected network request")

    def save_game(self, refs=None, title="Example Game"):
        game = games.normalize_igdb_game(
            {"id": 111, "name": title, "summary": "Description"}, "unused"
        )
        game["storeReferences"] = refs or []
        game = self.backend._save_game(111, game)
        return game

    def test_missing_default_catalog_key_provides_setup_state_without_network(self):
        self.config.unlink()
        self.backend.config(force=True)
        result = self.backend.handle({"op": "browse", "query": ""})
        self.assertTrue(result["setupRequired"])
        self.assertIn("igdb_client_id", result["warning"])
        self.assertEqual(self.calls, [])

    def configure_igdb(self, responder):
        self.config.write_text(
            json.dumps({"igdb_client_id": "test-client", "igdb_client_secret": "test-secret"})
        )
        self.backend.config(force=True)

        def request(url, method="GET", headers=None, body=None, *args):
            if "oauth2/token" in url:
                return {"access_token": "test-token", "expires_in": 3600}
            if "protondb.com" in url:
                return {"tier": "gold", "total": 12}
            return responder(url, body.decode())

        self.backend._request = request
        self.backend.catalogue.request = request

    def test_igdb_catalog_and_store_identities_are_separate(self):
        raw = {
            "id": 3498,
            "name": "Example Game",
            "summary": "Description",
            "cover": {"image_id": "co123"},
            "screenshots": [{"image_id": "sc123"}],
            "websites": [{"url": "https://store.steampowered.com/app/12345/"}],
        }
        self.configure_igdb(lambda url, body: [raw])
        result = self.backend.browse({"query": "Example Game"})
        self.assertEqual(result["providerName"], "IGDB")
        game = result["items"][0]
        self.assertNotEqual(game["id"], "3498")
        detail = self.backend.details({"gameId": game["id"]})["game"]
        self.assertEqual(detail["summary"], "Description")
        self.assertEqual(len(detail["screenshots"]), 1)
        compatibility = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(compatibility["url"], "https://www.protondb.com/app/12345")
        self.assertEqual(compatibility["tier"], "gold")

    def test_official_website_is_cleared_when_igdb_removes_it(self):
        with_link = games.normalize_igdb_game(
            {
                "id": 111,
                "name": "Example Game",
                "websites": [{"type": 1, "url": "https://example.org/game"}],
            }
        )
        saved = self.backend._save_game(111, with_link)
        self.assertEqual(saved["officialWebsite"], "https://example.org/game")
        without_link = games.normalize_igdb_game(
            {"id": 111, "name": "Example Game", "websites": []}
        )
        refreshed = self.backend._save_game(111, without_link)
        self.assertEqual(refreshed["id"], saved["id"])
        self.assertEqual(refreshed["officialWebsite"], "")

    def test_credentials_are_not_exposed_in_provider_errors(self):
        self.configure_igdb(lambda url, body: [])

        def rejected(*args):
            raise games.GamesError("HTTP 401 test-secret")

        self.backend.catalogue.request = rejected
        with self.assertRaisesRegex(games.GamesError, "authentication failed") as error:
            self.backend.catalogue.query("games", "fields name;")
        self.assertNotIn("test-secret", str(error.exception))

    def test_genre_platform_filter_options_are_cached(self):
        calls = []

        def respond(url, body):
            calls.append(url)
            return (
                [{"id": 4, "name": "Action"}]
                if url.endswith("genres")
                else [{"id": 1, "name": "PC"}]
            )

        self.configure_igdb(respond)
        result = self.backend._filter_options()
        self.assertEqual(
            result,
            {"genres": [{"id": 4, "name": "Action"}], "platforms": [{"id": 1, "name": "PC"}]},
        )
        self.assertEqual(self.backend._filter_options(), result)
        self.assertEqual(len(calls), 2)

    def test_browse_applies_genre_platform_and_year_filters(self):
        calls = []

        def respond(url, body):
            calls.append(body)
            return []

        self.configure_igdb(respond)
        self.backend.browse(
            {
                "query": "example",
                "filters": {
                    "genre": "4",
                    "platform": "1",
                    "sort": "-rating",
                    "fromYear": "2010",
                    "toYear": "2015",
                },
            }
        )
        self.assertEqual(len(calls), 1)
        self.assertIn('search "example";', calls[0])
        self.assertIn("genres = (4)", calls[0])
        self.assertIn("platforms = (1)", calls[0])
        self.assertIn("first_release_date >= 1262304000", calls[0])
        # IGDB search uses relevance; the API does not allow search plus sort.
        self.assertNotIn("sort ", calls[0])

    def test_discover_refresh_bypasses_fresh_cache(self):
        calls = []

        def respond(url, body):
            calls.append(body)
            return [{"id": 1, "name": "First Game" if len(calls) == 1 else "Newest Game"}]

        self.configure_igdb(respond)
        first = self.backend.browse({})
        self.assertEqual(self.backend.browse({}), first)
        refreshed = self.backend.browse({"refresh": True})
        self.assertEqual(first["items"][0]["title"], "First Game")
        self.assertEqual(refreshed["items"][0]["title"], "Newest Game")
        self.assertEqual(first["items"][0]["id"], refreshed["items"][0]["id"])
        self.assertEqual(len(calls), 2)

    def test_favorite_state_is_local_persistent_and_searchable(self):
        first = self.save_game(title="Example Game")
        second = self.backend._save_game(
            222, games.normalize_igdb_game({"id": 222, "name": "Other Game"}, "other")
        )
        self.backend.set_favorite({"gameId": first["id"], "favorite": True})
        result = self.backend.browse({"favorites": True, "query": "example", "offset": 0})
        self.assertEqual([game["title"] for game in result["items"]], ["Example Game"])
        self.assertTrue(result["items"][0]["favorite"])
        self.assertEqual(self.backend.browse({"favorites": True, "query": "missing"})["items"], [])
        self.backend.set_favorite({"gameId": first["id"], "favorite": False})
        self.assertEqual(self.backend.browse({"favorites": True})["items"], [])
        self.assertFalse(second.get("favorite", False))

    def test_legendary_json_runs_non_interactively(self):
        self.backend._which = lambda name: "/fake/legendary" if name == "legendary" else None
        self.backend._runner = Mock(
            return_value=subprocess.CompletedProcess(
                ["/fake/legendary", "list", "--json"], 0, "[]", ""
            )
        )
        result, status = self.backend._run_legendary_json(["list", "--json"])
        self.assertEqual(result, [])
        self.assertEqual(status, "ok")
        self.backend._runner.assert_called_once()
        self.assertEqual(
            self.backend._runner.call_args.args[0], ["/fake/legendary", "list", "--json"]
        )
        self.assertIs(self.backend._runner.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_protondb_lookup_uses_steam_ref_and_caches_rating(self):
        game = self.save_game([{"store": "steam", "externalId": "730"}])
        first = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(first["tier"], "gold")
        self.assertEqual(first["trendingTier"], "platinum")
        self.assertEqual(first["url"], "https://www.protondb.com/app/730")
        self.assertEqual(len(self.calls), 1)
        self.backend._request = Mock(side_effect=games.GamesError("offline"))
        second = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(second["tier"], "gold")
        self.backend._request.assert_not_called()

    def test_protondb_does_not_guess_without_a_store_or_library_match(self):
        game = self.save_game(title="Doom")
        result = self.backend.protondb({"gameId": game["id"]})
        self.assertFalse(result["available"])
        self.assertEqual(result["url"], "")
        self.assertEqual(self.calls, [])

    def test_protondb_uses_a_centralized_exact_steam_library_match(self):
        game = self.save_game()
        self.backend._library_snapshot = {
            "steam": {
                "items": [
                    {
                        "store": "steam",
                        "externalId": "123",
                        "title": game["title"],
                        "installed": False,
                        "launchable": False,
                    }
                ],
            }
        }
        self.backend._library_updated = self.backend._clock()
        result = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(result["url"], "https://www.protondb.com/app/123")
        self.assertIn("/summaries/123.json", self.calls[-1][0])

    def test_protondb_invalid_tier_becomes_unknown_and_keeps_numeric_page_link(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._request = lambda *args, **kwargs: {"tier": "surprise", "total": 3}
        result = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(result["tier"], "unknown")
        self.assertEqual(result["label"], "Unknown")
        self.assertEqual(result["url"], "https://www.protondb.com/app/123")

    def test_native_is_not_treated_as_a_protondb_rating_tier(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._request = lambda *args, **kwargs: {"tier": "native", "total": 3}
        result = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(result["tier"], "unknown")

    def test_protondb_outage_returns_unknown_with_outbound_link(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._request = Mock(side_effect=games.GamesError("offline"))
        result = self.backend.protondb({"gameId": game["id"]})
        self.assertEqual(result["tier"], "unknown")
        self.assertEqual(result["url"], "https://www.protondb.com/app/123")
        self.assertIn("unavailable", result["warning"])

    def test_manual_match_persists_and_can_be_cleared(self):
        game = self.save_game()
        self.backend.handle(
            {"op": "set_match", "gameId": game["id"], "store": "steam", "externalId": "123"}
        )
        self.assertEqual(self.backend._store_overrides(game["id"])["steam"], "123")
        self.backend.handle(
            {"op": "set_match", "gameId": game["id"], "store": "steam", "externalId": ""}
        )
        self.assertNotIn("steam", self.backend._store_overrides(game["id"]))

    def test_steam_launch_uses_structured_applaunch_arguments(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._library_snapshot = {
            "steam": {
                "available": True,
                "executable": "/usr/bin/steam",
                "ownershipKnown": False,
                "items": [
                    {
                        "store": "steam",
                        "externalId": "123",
                        "title": game["title"],
                        "installed": True,
                        "launchable": True,
                    }
                ],
                "ownedIds": [],
            },
            "epic": {"available": False, "items": [], "ownedIds": []},
            "umu": {"available": False},
        }
        self.backend._library_updated = self.backend._clock()
        result = self.backend.action({"gameId": game["id"], "actionId": "steam:play:123"})
        self.assertTrue(result["started"])
        self.backend._popen.assert_called_once()
        args = self.backend._popen.call_args.args[0]
        self.assertEqual(args, ["/usr/bin/steam", "-applaunch", "123"])

    def test_steam_install_opens_only_the_validated_appid_uri(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._library_snapshot = {
            "steam": {
                "available": True,
                "executable": "/usr/bin/steam",
                "ownershipKnown": True,
                "installationKnown": True,
                "items": [],
                "ownedIds": ["123"],
            },
            "epic": {"available": False, "items": [], "ownedIds": []},
            "umu": {"available": False},
        }
        self.backend._library_updated = self.backend._clock()
        result = self.backend.action({"gameId": game["id"], "actionId": "steam:install:123"})
        self.assertTrue(result["started"])
        self.assertEqual(
            self.backend._popen.call_args.args[0], ["/usr/bin/steam", "steam://install/123"]
        )

    def test_steam_uninstall_opens_steam_confirmation_uri(self):
        game = self.save_game([{"store": "steam", "externalId": "123"}])
        self.backend._library_snapshot = {
            "steam": {
                "available": True,
                "executable": "/usr/bin/steam",
                "ownershipKnown": True,
                "installationKnown": True,
                "ownedIds": ["123"],
                "items": [
                    {
                        "store": "steam",
                        "externalId": "123",
                        "title": game["title"],
                        "installed": True,
                        "launchable": True,
                    }
                ],
            },
            "epic": {"available": False, "items": [], "ownedIds": []},
            "umu": {"available": False},
        }
        self.backend._library_updated = self.backend._clock()
        result = self.backend.action({"gameId": game["id"], "actionId": "steam:uninstall:123"})
        self.assertTrue(result["started"])
        self.assertEqual(
            self.backend._popen.call_args.args[0], ["/usr/bin/steam", "steam://uninstall/123"]
        )

    def test_epic_uninstall_uses_legendary_with_structured_arguments(self):
        game = self.save_game([{"store": "epic", "externalId": "Catnip"}])
        self.backend._which = lambda name: "/usr/bin/legendary" if name == "legendary" else None
        self.backend._library_snapshot = {
            "steam": {"available": False, "items": [], "ownedIds": []},
            "epic": {
                "available": True,
                "ownershipKnown": True,
                "installationKnown": True,
                "ownedIds": ["Catnip"],
                "items": [
                    {
                        "store": "epic",
                        "externalId": "Catnip",
                        "title": game["title"],
                        "installed": True,
                        "launchable": True,
                    }
                ],
            },
            "umu": {"available": False},
        }
        self.backend._library_updated = self.backend._clock()
        result = self.backend.action({"gameId": game["id"], "actionId": "epic:uninstall:Catnip"})
        self.assertTrue(result["started"])
        self.assertEqual(
            self.backend._popen.call_args.args[0],
            ["/usr/bin/legendary", "--yes", "uninstall", "Catnip"],
        )

    def test_detached_launcher_reports_a_quick_nonzero_exit(self):
        self.backend._popen = subprocess.Popen
        with self.assertRaisesRegex(games.GamesError, "Exit code 7"):
            self.backend._spawn_detached(
                [sys.executable, "-c", "raise SystemExit(7)"],
                "Test launcher could not start.",
            )

    def test_steam_public_api_private_visibility_stays_unknown(self):
        self.config.write_text(
            json.dumps(
                {
                    "steam_api_key": "local-test-key",
                    "steam_id": "76561198000000000",
                }
            )
        )
        self.backend.config(force=True)
        self.backend._request = lambda *args, **kwargs: {
            "response": {"players": [{"communityvisibilitystate": 1}]}
        }
        state = self.backend._steam_owned_state()
        self.assertTrue(state["configured"])
        self.assertFalse(state["known"])
        self.assertEqual(len(self.calls), 0)

    def test_steam_api_key_without_steamid64_requests_the_missing_id(self):
        self.config.write_text(json.dumps({"steam_api_key": "local-test-key", "steam_id": ""}))
        self.backend.config(force=True)
        state = self.backend._steam_owned_state()
        self.assertFalse(state["configured"])
        self.assertIn("17-digit SteamID64", state["message"])
        self.assertEqual(self.calls, [])

    def test_steam_api_without_a_games_array_is_not_evidence_of_no_ownership(self):
        self.config.write_text(
            json.dumps(
                {
                    "steam_api_key": "local-test-key",
                    "steam_id": "76561198000000000",
                }
            )
        )
        self.backend.config(force=True)
        responses = iter(
            [
                {"response": {"players": [{"communityvisibilitystate": 3}]}},
                {"response": {}},
            ]
        )
        self.backend._request = lambda *args, **kwargs: next(responses)
        state = self.backend._steam_owned_state()
        self.assertFalse(state["known"])
        self.assertIn("private or unavailable", state["message"])

    def test_epic_launch_uses_umu_environment_and_structured_arguments(self):
        game = self.save_game(
            [
                {"store": "epic", "externalId": "EpicOffer"},
                {"store": "steam", "externalId": "123"},
            ]
        )
        self.backend._library_snapshot = {
            "steam": {"available": True, "ownershipKnown": False, "items": [], "ownedIds": []},
            "epic": {
                "available": True,
                "ownershipKnown": True,
                "installationKnown": True,
                "ownedIds": ["Catnip"],
                "items": [
                    {
                        "store": "epic",
                        "externalId": "Catnip",
                        "title": game["title"],
                        "installed": True,
                        "launchable": True,
                    }
                ],
            },
            "umu": {"available": True},
        }
        self.backend._library_updated = self.backend._clock()
        self.backend._which = lambda name: {
            "legendary": "/fake/legendary",
            "umu-run": "/fake/umu-run",
        }.get(name)
        result = self.backend.action({"gameId": game["id"], "actionId": "epic:play:Catnip"})
        self.assertTrue(result["started"])
        args = self.backend._popen.call_args.args[0]
        self.assertEqual(
            args, ["/fake/legendary", "launch", "Catnip", "--wrapper", "umu-run", "--no-wine"]
        )
        env = self.backend._popen.call_args.kwargs["env"]
        self.assertEqual(env["STORE"], "egs")
        self.assertEqual(env["GAMEID"], "umu-123")
        self.assertTrue(
            env["WINEPREFIX"].endswith(
                "/prefixes/egs/" + games.hashlib.sha256(b"egs:catnip").hexdigest()[:24]
            )
        )

    def test_epic_launch_falls_back_to_legendary_when_umu_is_missing(self):
        game = self.save_game([{"store": "epic", "externalId": "Catnip"}])
        self.backend._library_snapshot = {
            "steam": {"available": False, "ownershipKnown": False, "items": [], "ownedIds": []},
            "epic": {
                "available": True,
                "ownershipKnown": True,
                "installationKnown": True,
                "ownedIds": ["Catnip"],
                "items": [
                    {
                        "store": "epic",
                        "externalId": "Catnip",
                        "title": game["title"],
                        "installed": True,
                        "launchable": True,
                    }
                ],
            },
            "umu": {"available": False},
        }
        self.backend._library_updated = self.backend._clock()
        self.backend._which = lambda name: "/fake/legendary" if name == "legendary" else None
        self.backend.action({"gameId": game["id"], "actionId": "epic:play:Catnip"})
        self.assertEqual(
            self.backend._popen.call_args.args[0], ["/fake/legendary", "launch", "Catnip"]
        )
        self.assertNotIn("GAMEID", self.backend._popen.call_args.kwargs["env"])

    def test_epic_install_requires_known_ownership_and_uses_legendary(self):
        game = self.save_game([{"store": "epic", "externalId": "Catnip"}])
        self.backend._library_snapshot = {
            "steam": {"available": False, "ownershipKnown": False, "items": [], "ownedIds": []},
            "epic": {
                "available": True,
                "ownershipKnown": True,
                "installationKnown": True,
                "ownedIds": ["Catnip"],
                "items": [
                    {
                        "store": "epic",
                        "externalId": "Catnip",
                        "title": game["title"],
                        "installed": False,
                    }
                ],
            },
        }
        self.backend._library_updated = self.backend._clock()
        self.backend._which = lambda name: "/fake/legendary" if name == "legendary" else None
        result = self.backend.action({"gameId": game["id"], "actionId": "epic:install:Catnip"})
        self.assertTrue(result["started"])
        self.assertEqual(
            self.backend._popen.call_args.args[0], ["/fake/legendary", "--yes", "install", "Catnip"]
        )


if __name__ == "__main__":
    unittest.main()
