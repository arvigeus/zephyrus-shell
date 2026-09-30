import io
import json
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch
from zoneinfo import ZoneInfo

from attention import backend, nextcloud, weather


class WeatherTests(unittest.TestCase):
    def test_forecast_normalization_and_cached_fallback(self):
        payload = {
            "current": {"time": "2026-09-29T22:00", "temperature_2m": 28.2,
                        "apparent_temperature": 34.0, "relative_humidity_2m": 90,
                        "wind_speed_10m": 4.3, "weather_code": 2, "is_day": 0},
            "daily": {"time": [(datetime(2026, 9, 29) + timedelta(days=day)).date().isoformat() for day in range(7)],
                      "weather_code": [61] * 7,
                      "temperature_2m_max": [30] * 7,
                      "temperature_2m_min": [24] * 7},
        }
        location = {"name": "Ha Long", "latitude": 20.95045, "longitude": 107.07336,
                    "timezone": "Asia/Ho_Chi_Minh"}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "weather.json"
            first_time = datetime(2026, 9, 29, 22, tzinfo=ZoneInfo("Asia/Ho_Chi_Minh")).timestamp()
            def opener(_request, timeout):
                self.assertEqual(timeout, 15)
                query = parse_qs(urlsplit(_request.full_url).query)
                self.assertEqual(query["hourly"], ["temperature_2m,weather_code,is_day,precipitation_probability"])
                return io.BytesIO(json.dumps(payload).encode())
            fresh = weather.fetch(location, cache, opener=opener, now=lambda: first_time)
            self.assertEqual((fresh["current"]["icon"], fresh["days"][0]["icon"]),
                             ("cloud-moon", "cloud-rain"))
            self.assertEqual(len(fresh["days"]), 7)
            saved = weather.fetch(location, cache, opener=lambda *_args, **_kwargs: self.fail("Cache missed"), now=lambda: first_time + 100)
            self.assertFalse(saved["stale"])
            def unavailable(_request, timeout):
                raise OSError("offline")
            stale = weather.fetch(location, cache, opener=unavailable, now=lambda: first_time + weather.CACHE_AGE + 1)
            self.assertTrue(stale["stale"])
            next_day = weather.fetch(location, cache, opener=unavailable, now=lambda: first_time + 24 * 60 * 60)
            self.assertEqual(next_day["local_date"], "2026-09-30")

    def hourly_payload(self):
        return {
            "current": {"time": "2026-09-30T17:15", "temperature_2m": 32.6,
                        "apparent_temperature": 39.1, "relative_humidity_2m": 64,
                        "wind_speed_10m": 11.9, "weather_code": 1, "is_day": 1},
            "daily": {"time": [(date(2026, 9, 30) + timedelta(days=i)).isoformat() for i in range(7)],
                      "weather_code": [51] * 7, "temperature_2m_max": [33] * 7,
                      "temperature_2m_min": [27] * 7},
            "hourly": {"time": [(datetime(2026, 9, 30, 16) + timedelta(hours=i)).isoformat(timespec="minutes") for i in range(32)],
                       "temperature_2m": [31] * 32, "weather_code": [2] * 32,
                       "is_day": [1, 1] + [0] * 30, "precipitation_probability": [0, 0, None] + [65] * 29},
        }

    def test_current_daily_and_hourly_have_distinct_conditions_and_local_times(self):
        payload = self.hourly_payload()
        result = weather.normalize(payload, {"name": "Ha Long"})
        self.assertEqual(result["current"]["icon"], "sun")
        self.assertEqual(result["days"][0]["icon"], "cloud-drizzle")
        self.assertEqual(len(result["hours"]), 24)
        self.assertEqual(result["hours"][0]["time"], "2026-09-30T18:00")
        self.assertEqual(result["hours"][0]["icon"], "cloud-moon")
        self.assertIsNone(result["hours"][0]["precipitation_probability"])
        self.assertEqual(result["hours"][6]["time"], "2026-10-01T00:00")
        payload["current"]["time"] = "2026-09-30T18:00"
        self.assertEqual(weather.normalize(payload, {"name": "Ha Long"})["hours"][0]["time"], "2026-09-30T19:00")

    def test_incomplete_hourly_data_is_not_silently_misaligned(self):
        payload = self.hourly_payload()
        payload["hourly"]["is_day"].pop()
        with self.assertRaisesRegex(weather.WeatherError, "hourly"):
            weather.normalize(payload, {"name": "Ha Long"})

    def outlook(self, codes, *, daylight=range(6, 18)):
        rows = [{"group": weather.condition_group(code), "hour": hour, "is_day": hour in daylight}
                for hour, code in enumerate(codes)]
        return weather.daily_outlook(rows, 61)

    def test_sunny_day_with_short_drizzle_keeps_sunny_icon_and_mentions_timing(self):
        codes = [0] * 24
        codes[12:14] = [51, 51]
        result = self.outlook(codes)
        self.assertEqual(result["icon"], "sun")
        self.assertEqual(result["description"], "Mostly sunny, with drizzle in the afternoon")

    def test_rainy_day_mentions_sunny_breaks(self):
        codes = [61] * 24
        codes[14:17] = [0] * 3
        result = self.outlook(codes)
        self.assertEqual(result["icon"], "cloud-rain")
        self.assertEqual(result["description"], "Rain for much of the day, with sunny breaks")

    def test_cloudy_day_is_not_made_sunny_by_clear_nights(self):
        codes = [0] * 24
        codes[6:18] = [3] * 12
        self.assertEqual(self.outlook(codes)["description"], "Mostly cloudy")
        codes[:3] = [61] * 3
        self.assertEqual(self.outlook(codes)["description"], "Mostly cloudy, with rain overnight")

    def test_brief_storm_freezing_rain_and_snow_are_not_omitted(self):
        for code, name in [(95, "thunderstorms"), (66, "freezing rain"), (71, "snow")]:
            codes = [0] * 24
            codes[19] = code
            codes[12] = 51
            self.assertIn(name + " in the evening", self.outlook(codes)["description"])

    def test_mixed_cloud_fog_and_dry_breaks(self):
        self.assertEqual(self.outlook([2] * 24)["description"], "A mix of sun and cloud")
        self.assertEqual(self.outlook([45] * 24)["icon"], "cloud-fog")
        self.assertEqual(self.outlook([45] * 3 + [0] * 21)["description"], "Mostly sunny, with fog overnight")
        codes = [61] * 24
        codes[10:14] = [3] * 4
        self.assertEqual(self.outlook(codes)["description"], "Rain for much of the day, with dry breaks")

    def test_multiple_secondary_conditions_are_preserved(self):
        codes = [0] * 24
        codes[8] = 66
        codes[12] = 71
        codes[19] = 95
        summary = self.outlook(codes)["description"]
        self.assertIn("freezing rain in the morning", summary)
        self.assertIn("snow in the afternoon", summary)
        self.assertIn("thunderstorms in the evening", summary)

    def test_full_day_summaries_are_not_limited_to_next_24_hours(self):
        payload = self.hourly_payload()
        start = datetime(2026, 9, 30)
        payload["hourly"] = {"time": [(start + timedelta(hours=i)).isoformat(timespec="minutes") for i in range(168)],
                             "temperature_2m": [30] * 168, "weather_code": [0] * 168,
                             "is_day": [int(6 <= i % 24 < 18) for i in range(168)],
                             "precipitation_probability": [0] * 168}
        payload["hourly"]["weather_code"][6 * 24:] = [61] * 24
        result = weather.normalize(payload, {"name": "Ha Long"})
        self.assertEqual(result["days"][0]["icon"], "sun")
        self.assertEqual(result["days"][6]["icon"], "cloud-rain")
        self.assertEqual(result["days"][6]["summary_source"], "hourly")
        self.assertEqual(len(result["hours"]), 24)
        self.assertEqual(self.outlook([0] * 8)["summary_source"], "daily")

    def test_legacy_cache_refetches_hourly_data_but_survives_offline(self):
        location = {"name": "Ha Long", "latitude": 20.95045, "longitude": 107.07336,
                    "timezone": "Asia/Ho_Chi_Minh"}
        payload = self.hourly_payload()
        timestamp = datetime(2026, 9, 30, 17, 15, tzinfo=ZoneInfo(location["timezone"])).timestamp()
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "weather.json"
            legacy = weather.normalize(payload, location)
            del legacy["hours"]
            cache.write_text(json.dumps({"key": [location["latitude"], location["longitude"], location["timezone"]],
                                         "fetched_at": timestamp, "forecast": legacy}))
            def offline(*_args, **_kwargs):
                raise OSError("offline")
            saved = weather.fetch(location, cache, opener=offline, now=lambda: timestamp + 1)
            self.assertTrue(saved["stale"])
            self.assertEqual(saved["current"], legacy["current"])
            fresh = weather.fetch(location, cache, opener=lambda *_args, **_kwargs: io.BytesIO(json.dumps(payload).encode()),
                                  now=lambda: timestamp + 2)
            self.assertEqual(len(fresh["hours"]), 24)
            self.assertFalse(fresh["stale"])


class NextcloudTests(unittest.TestCase):
    def test_future_recurring_task_is_withheld(self):
        zone = ZoneInfo("Asia/Ho_Chi_Minh")
        future = date.today() + timedelta(days=180)
        todo = ("BEGIN:VCALENDAR\nBEGIN:VTODO\nSUMMARY:Annual payment\nRRULE:FREQ=YEARLY\n"
                "DUE;VALUE=DATE:" + future.strftime("%Y%m%d") + "\nEND:VTODO\nEND:VCALENDAR")
        tasks = nextcloud.tasks_from([("https://cloud.example/tasks/annual.ics", '"1"', todo)],
                                     {"name": "Tasks", "slug": "tasks"}, zone)
        self.assertEqual(tasks, [])

    def test_create_event_uses_new_ical_object_and_selected_calendar(self):
        client = nextcloud.Client.__new__(nextcloud.Client)
        client.propfind = lambda: [{"url": "https://cloud.example/calendars/personal/",
                                    "slug": "personal", "name": "Personal",
                                    "components": {"VEVENT"}, "writable": True}]
        writes = []
        client.request = lambda method, href, body=None, headers=None: (writes.append((method, href, body, headers)) or (b"", {}))
        result = client.save_item({}, "VEVENT", {
            "collection": "personal", "summary": "Lunch", "description": "With Ana",
            "start_date": "2026-10-01", "end_date": "2026-10-01", "all_day": False,
            "start_time": "12:00", "end_time": "13:00",
        })
        self.assertTrue(result["saved"])
        method, href, body, headers = writes[0]
        self.assertEqual(method, "PUT")
        self.assertTrue(href.startswith("https://cloud.example/calendars/personal/"))
        self.assertTrue(href.endswith(".ics"))
        self.assertEqual(headers["If-None-Match"], "*")
        self.assertIn(b"BEGIN:VEVENT", body)
        self.assertIn(b"DTSTART:", body)
        self.assertIn(b"DTEND:", body)

    def test_edit_task_preserves_other_properties_and_checks_etag(self):
        client = nextcloud.Client.__new__(nextcloud.Client)
        client.propfind = lambda: [{"url": "https://cloud.example/calendars/tasks/",
                                    "slug": "tasks", "name": "Tasks",
                                    "components": {"VTODO"}, "writable": True}]
        original = (b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:existing\r\n"
                    b"SUMMARY:Old\r\nPRIORITY:1\r\nEND:VTODO\r\nEND:VCALENDAR\r\n")
        writes = []
        def request(method, href, body=None, headers=None):
            if method == "GET":
                return original, {"ETag": '"abc"'}
            writes.append((method, href, body, headers))
            return b"", {}
        client.request = request
        client.save_item({}, "VTODO", {"collection": "tasks", "href": "https://cloud.example/calendars/tasks/item.ics",
                                       "etag": '"abc"', "summary": "Updated", "description": "Keep priority",
                                       "due": "2026-10-02"})
        self.assertEqual(writes[0][3]["If-Match"], '"abc"')
        self.assertIn(b"UID:existing", writes[0][2])
        self.assertIn(b"PRIORITY:1", writes[0][2])
        self.assertIn(b"SUMMARY:Updated", writes[0][2])
        self.assertIn(b"DUE;VALUE=DATE:20261002", writes[0][2])
        with self.assertRaisesRegex(nextcloud.NextcloudError, "changed"):
            client.save_item({}, "VTODO", {"collection": "tasks",
                                           "href": "https://cloud.example/calendars/tasks/item.ics",
                                           "etag": '"older"', "summary": "Oops"})
        self.assertEqual(len(writes), 1)

    def test_attention_includes_events_beyond_current_month(self):
        today = date.today()
        month_start = today.replace(day=1)
        next_month = (month_start + timedelta(days=32)).replace(day=1)
        future = today + timedelta(days=50)
        event = ("BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Future event\nDTSTART;VALUE=DATE:"
                 + future.strftime("%Y%m%d") + "\nDTEND;VALUE=DATE:"
                 + (future + timedelta(days=1)).strftime("%Y%m%d")
                 + "\nEND:VEVENT\nEND:VCALENDAR")
        class FakeClient:
            def __init__(self, _config, opener=None):
                pass
            def propfind(self):
                return [{"url": "https://cloud.example/personal/", "slug": "personal",
                         "name": "Personal", "components": {"VEVENT"}}]
            def report(self, _collection, _kind, _start=None, _end=None):
                return [("https://cloud.example/personal/future.ics", '"1"', event)]
        with patch.object(nextcloud, "Client", FakeClient):
            result = nextcloud.snapshot({}, start=month_start.isoformat(), end=next_month.isoformat())
        self.assertIn(future.isoformat(), [item["date"] for item in result["events"]])

    def test_omitted_calendar_filter_includes_all(self):
        event = """BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Meeting\nDTSTART:20260930T090000\nDTEND:20260930T100000\nEND:VEVENT\nEND:VCALENDAR"""
        task = """BEGIN:VCALENDAR\nBEGIN:VTODO\nSUMMARY:Task\nEND:VTODO\nEND:VCALENDAR"""
        class FakeClient:
            def __init__(self, _config, opener=None):
                pass
            def propfind(self):
                return [
                    {"url": "https://cloud.example/personal/", "slug": "personal", "name": "Personal", "components": {"VEVENT"}},
                    {"url": "https://cloud.example/work/", "slug": "work", "name": "Work", "components": {"VEVENT"}},
                    {"url": "https://cloud.example/tasks/", "slug": "tasks", "name": "Tasks", "components": {"VTODO"}},
                ]
            def report(self, collection, kind, _start=None, _end=None):
                contents = event if kind == "VEVENT" else task
                return [(collection["url"] + "item.ics", '"1"', contents)]
        with patch.object(nextcloud, "Client", FakeClient):
            all_items = nextcloud.snapshot({}, start="2026-09-01", end="2026-10-15")
            selected = nextcloud.snapshot({"calendars": ["Personal"]}, start="2026-09-01", end="2026-10-15")
        self.assertEqual({item["calendar"] for item in all_items["events"]}, {"Personal", "Work"})
        self.assertEqual({item["calendar"] for item in selected["events"]}, {"Personal"})
        self.assertEqual(all_items["task_count"], 1)

    def test_discovers_calendars_and_task_lists(self):
        xml = b'''<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response><d:href>/remote.php/dav/calendars/alice/</d:href></d:response>
          <d:response><d:href>/remote.php/dav/calendars/alice/personal/</d:href><d:propstat>
            <d:prop><d:displayname>Personal</d:displayname><d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
            <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/remote.php/dav/calendars/alice/tasks/</d:href><d:propstat>
            <d:prop><d:displayname>Tasks</d:displayname><d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
            <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        </d:multistatus>'''
        client = nextcloud.Client.__new__(nextcloud.Client)
        client.base = "https://cloud.example/"
        client.home = "https://cloud.example/remote.php/dav/calendars/alice/"
        client.request = lambda *_args, **_kwargs: (xml, {})
        collections = client.propfind()
        self.assertEqual([(item["slug"], item["components"]) for item in collections],
                         [("personal", {"VEVENT"}), ("tasks", {"VTODO"})])

    def test_recurring_event_and_completed_task_filter(self):
        zone = ZoneInfo("Asia/Ho_Chi_Minh")
        calendar = {"name": "Personal"}
        event = """BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:meeting\nSUMMARY:Team\\, weekly\nDTSTART:20260929T090000\nDTEND:20260929T100000\nRRULE:FREQ=DAILY;COUNT=3\nEXDATE:20260930T090000\nEND:VEVENT\nEND:VCALENDAR"""
        results = nextcloud.events_from([("https://cloud.example/a.ics", '"1"', event)], calendar,
                                        datetime(2026, 9, 29, tzinfo=zone),
                                        datetime(2026, 10, 3, tzinfo=zone), zone)
        self.assertEqual([item["date"] for item in results], ["2026-09-29", "2026-10-01"])
        self.assertEqual(results[0]["summary"], "Team, weekly")
        todo = """BEGIN:VCALENDAR\nBEGIN:VTODO\nSUMMARY:Open task\nDUE;VALUE=DATE:20260930\nEND:VTODO\nBEGIN:VTODO\nSUMMARY:Done task\nSTATUS:COMPLETED\nEND:VTODO\nEND:VCALENDAR"""
        tasks = nextcloud.tasks_from([("https://cloud.example/t.ics", '"2"', todo)],
                                     {"name": "Tasks"}, zone)
        self.assertEqual([(task["summary"], task["due"]) for task in tasks],
                         [("Open task", "2026-09-30")])

    def test_task_completion_uses_etag(self):
        client = nextcloud.Client.__new__(nextcloud.Client)
        writes = []
        def request(method, href, body=None, headers=None):
            if method == "GET":
                return b"BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:task\r\nSUMMARY:Example\r\nEND:VTODO\r\nEND:VCALENDAR\r\n", {"ETag": '"abc"'}
            writes.append((method, href, body.decode(), headers))
            return b"", {}
        client.request = request
        client.complete_task({"href": "https://cloud.example/task.ics", "etag": '"abc"'})
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0][0], "PUT")
        self.assertIn("STATUS:COMPLETED", writes[0][2])
        self.assertIn("PERCENT-COMPLETE:100", writes[0][2])
        self.assertEqual(writes[0][3]["If-Match"], '"abc"')


class CacheTests(unittest.TestCase):
    def test_saved_calendar_backoff_avoids_repeated_network_fetches(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = [1000000.0]
            sample = {"events": [], "tasks": [], "calendars": [], "task_count": 0}
            with patch.object(backend, "CLOUD_CACHE", Path(directory) / "nextcloud.json"), \
                 patch.object(backend.time, "time", side_effect=lambda: clock[0]), \
                 patch.object(backend.nextcloud, "snapshot", return_value=sample) as fetch:
                first = backend.cloud_snapshot({"url": "https://cloud.example/", "username": "alice"},
                                               "2026-09-01", "2026-10-01")
                self.assertFalse(first["stale"])
                backend.cloud_snapshot({"url": "https://cloud.example/", "username": "alice"},
                                       "2026-09-01", "2026-10-01")
                self.assertEqual(fetch.call_count, 1)
                clock[0] += backend.CLOUD_CACHE_AGE + 1
                due = backend.cloud_snapshot({"url": "https://cloud.example/", "username": "alice"},
                                             "2026-09-01", "2026-10-01")
                self.assertTrue(due["refresh_due"])
                fetch.side_effect = nextcloud.NextcloudError("offline")
                failed = backend.cloud_snapshot({"url": "https://cloud.example/", "username": "alice"},
                                                "2026-09-01", "2026-10-01", refresh=True)
                self.assertTrue(failed["stale"])
                again = backend.cloud_snapshot({"url": "https://cloud.example/", "username": "alice"},
                                               "2026-09-01", "2026-10-01")
                self.assertFalse(again["refresh_due"])
                self.assertEqual(fetch.call_count, 2)


if __name__ == "__main__":
    unittest.main()
