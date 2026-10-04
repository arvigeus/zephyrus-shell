"""Small CalDAV reader for Nextcloud calendars and task lists."""

import re
import xml.etree.ElementTree as ET
from datetime import UTC, date, datetime, timedelta
from urllib.parse import quote, unquote, urljoin
from uuid import uuid4
from zoneinfo import ZoneInfo

from dateutil.rrule import rrulestr

from services.nextcloud import DAVClient, NextcloudError

DAV = "DAV:"
CAL = "urn:ietf:params:xml:ns:caldav"
NS = {"d": DAV, "c": CAL}


class Client(DAVClient):
    def __init__(self, config, *, opener=None, provider=None):
        scope = "remote.php/dav/calendars/" + quote(config.get("username", ""), safe="") + "/"
        super().__init__(config, scope=scope, opener=opener, provider=provider)

    def propfind(self):
        body = b"""<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><d:resourcetype/><c:supported-calendar-component-set/><d:current-user-privilege-set/></d:prop>
</d:propfind>"""
        raw, _ = self.request(
            "PROPFIND",
            self.home,
            body,
            {"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
        )
        try:
            document = ET.fromstring(raw)
        except ET.ParseError as error:
            raise NextcloudError("Nextcloud returned invalid calendar discovery data.") from error
        collections = []
        for response in document.findall("d:response", NS):
            href = response.findtext("d:href", default="", namespaces=NS)
            url = urljoin(self.base, href)
            if url.rstrip("/") == self.home.rstrip("/") or not url.startswith(self.home):
                continue
            for propstat in response.findall("d:propstat", NS):
                if " 200 " not in propstat.findtext("d:status", default="", namespaces=NS):
                    continue
                prop = propstat.find("d:prop", NS)
                if prop is None or prop.find("d:resourcetype/c:calendar", NS) is None:
                    continue
                components = {
                    node.get("name")
                    for node in prop.findall("c:supported-calendar-component-set/c:comp", NS)
                }
                privileges = {
                    node.tag.rsplit("}", 1)[-1]
                    for node in prop.findall("d:current-user-privilege-set/d:privilege/*", NS)
                }
                collections.append(
                    {
                        "url": url,
                        "slug": unquote(url.rstrip("/").rsplit("/", 1)[-1]),
                        "name": prop.findtext("d:displayname", default="", namespaces=NS)
                        or unquote(url.rstrip("/").rsplit("/", 1)[-1]),
                        "components": components or {"VEVENT", "VTODO"},
                        "writable": bool({"write", "write-content", "all"} & privileges)
                        and bool({"bind", "all"} & privileges),
                    }
                )
        return collections

    def report(self, collection, kind, start=None, end=None):
        time_range = ""
        if start and end:
            time_range = '<c:time-range start="' + start + '" end="' + end + '"/>'
        body = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            "<d:prop><d:getetag/><c:calendar-data/></d:prop>"
            '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="'
            + kind
            + '">'
            + time_range
            + "</c:comp-filter></c:comp-filter></c:filter>"
            "</c:calendar-query>"
        ).encode()
        raw, _ = self.request(
            "REPORT",
            collection["url"],
            body,
            {"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
        )
        try:
            document = ET.fromstring(raw)
        except ET.ParseError as error:
            raise NextcloudError("Nextcloud returned invalid calendar data.") from error
        entries = []
        for response in document.findall("d:response", NS):
            href = response.findtext("d:href", default="", namespaces=NS)
            for propstat in response.findall("d:propstat", NS):
                if " 200 " not in propstat.findtext("d:status", default="", namespaces=NS):
                    continue
                prop = propstat.find("d:prop", NS)
                if prop is None:
                    continue
                data = prop.findtext("c:calendar-data", default="", namespaces=NS)
                if data:
                    entries.append(
                        (
                            urljoin(self.base, href),
                            prop.findtext("d:getetag", default="", namespaces=NS),
                            data,
                        )
                    )
        return entries

    def complete_task(self, task):
        href, etag = task.get("href", ""), task.get("etag", "")
        if not href or not etag:
            raise NextcloudError("This task cannot be updated. Refresh and try again.")
        raw, headers = self.request("GET", href)
        if headers.get("ETag") != etag:
            raise NextcloudError("The task changed on Nextcloud. Refresh and try again.")
        data = raw.decode("utf-8")
        match = re.search(r"(?ims)^BEGIN:VTODO\r?\n(.*?)^END:VTODO\r?$", data)
        if not match:
            raise NextcloudError("The task could not be found in its calendar item.")
        block = match.group(1)
        if "RRULE:" in block.upper():
            raise NextcloudError("Recurring tasks must be completed in Nextcloud.")
        if re.search(r"(?mi)^STATUS:COMPLETED\r?$", block):
            return
        newline = "\r\n" if "\r\n" in data else "\n"
        for field, value in (
            ("STATUS", "COMPLETED"),
            ("PERCENT-COMPLETE", "100"),
            ("COMPLETED", datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")),
        ):
            pattern = rf"(?mi)^{field}(?:;[^:]*)?:[^\r\n]*"
            if re.search(pattern, block):
                block = re.sub(pattern, field + ":" + value, block, count=1)
            else:
                block += field + ":" + value + newline
        updated = data[: match.start(1)] + block + data[match.end(1) :]
        self.request(
            "PUT",
            href,
            updated.encode(),
            {"Content-Type": "text/calendar; charset=utf-8", "If-Match": etag},
        )

    def save_item(self, config, kind, entry):
        if kind not in ("VTODO", "VEVENT") or not isinstance(entry, dict):
            raise NextcloudError("The calendar item is invalid.")
        slug = str(entry.get("collection", ""))
        selection = config.get("task_lists" if kind == "VTODO" else "calendars")
        if selection is not None and not isinstance(selection, list):
            raise NextcloudError("The calendar selection in attention.json is invalid.")
        collection = next(
            (
                item
                for item in self.propfind()
                if item["slug"] == slug
                and kind in item["components"]
                and item["writable"]
                and (selection is None or slug in selection or item["name"] in selection)
            ),
            None,
        )
        if collection is None:
            raise NextcloudError("Choose a writable calendar or task list.")
        fields = entry_fields(kind, entry)
        href = str(entry.get("href", ""))
        if href:
            etag = str(entry.get("etag", ""))
            if not href.startswith(collection["url"]) or not etag:
                raise NextcloudError("This item cannot be updated. Refresh and try again.")
            raw, headers = self.request("GET", href)
            if headers.get("ETag") != etag:
                raise NextcloudError("This item changed on Nextcloud. Refresh and try again.")
            updated = update_ical(raw.decode("utf-8"), kind, fields)
            self.request(
                "PUT",
                href,
                updated.encode("utf-8"),
                {"Content-Type": "text/calendar; charset=utf-8", "If-Match": etag},
            )
        else:
            identity = uuid4().hex
            href = collection["url"] + identity + ".ics"
            stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
            lines = [
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "PRODID:-//Zephyrus Shell//Attention//EN",
                "BEGIN:" + kind,
                "UID:" + identity + "@zephyrus-shell",
                "DTSTAMP:" + stamp,
                *fields,
                "END:" + kind,
                "END:VCALENDAR",
            ]
            self.request(
                "PUT",
                href,
                serialize_ical(lines),
                {"Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*"},
            )
        return {"saved": True}


def escape_text(value):
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace(",", "\\,")
        .replace(";", "\\;")
    )


def entry_fields(kind, entry):
    title = str(entry.get("summary", "")).strip()
    description = str(entry.get("description", "")).strip()
    if not title or len(title) > 250 or len(description) > 10000:
        raise NextcloudError(
            "Enter a title of at most 250 characters and notes of at most 10,000 characters."
        )
    fields = ["SUMMARY:" + escape_text(title)]
    if description:
        fields.append("DESCRIPTION:" + escape_text(description))
    try:
        if kind == "VTODO":
            due = str(entry.get("due", "")).strip()
            if due:
                fields.append("DUE;VALUE=DATE:" + date.fromisoformat(due).strftime("%Y%m%d"))
        else:
            starts = date.fromisoformat(str(entry.get("start_date", "")))
            ends = date.fromisoformat(str(entry.get("end_date", "")))
            if entry.get("all_day"):
                if ends < starts:
                    raise ValueError()
                fields.extend(
                    (
                        "DTSTART;VALUE=DATE:" + starts.strftime("%Y%m%d"),
                        "DTEND;VALUE=DATE:" + (ends + timedelta(days=1)).strftime("%Y%m%d"),
                    )
                )
            else:
                zone = datetime.now().astimezone().tzinfo
                start_time = datetime.strptime(str(entry.get("start_time", "")), "%H:%M").time()
                end_time = datetime.strptime(str(entry.get("end_time", "")), "%H:%M").time()
                start_at = datetime.combine(starts, start_time, tzinfo=zone)
                end_at = datetime.combine(ends, end_time, tzinfo=zone)
                if end_at <= start_at:
                    raise ValueError()
                fields.extend(
                    (
                        "DTSTART:" + start_at.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ"),
                        "DTEND:" + end_at.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ"),
                    )
                )
    except (ValueError, OverflowError) as error:
        raise NextcloudError(
            "Check the date and time. Use YYYY-MM-DD and HH:MM, with the end after the start."
        ) from error
    return fields


def unfold_ical(data):
    lines = []
    for line in data.splitlines():
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    return lines


def serialize_ical(lines):
    folded = []
    for line in lines:
        current = ""
        for character in line:
            if len((current + character).encode("utf-8")) > 75:
                folded.append(current)
                current = " " + character
            else:
                current += character
        folded.append(current)
    return ("\r\n".join(folded) + "\r\n").encode("utf-8")


def update_ical(data, kind, fields):
    lines = unfold_ical(data)
    opening, closing = "BEGIN:" + kind, "END:" + kind
    starts = [index for index, line in enumerate(lines) if line.upper() == opening]
    if len(starts) != 1:
        raise NextcloudError("Recurring or grouped items must be edited in Nextcloud.")
    start = starts[0]
    try:
        end = lines.index(closing, start + 1)
    except ValueError as error:
        raise NextcloudError("Nextcloud returned an invalid calendar item.") from error
    block = lines[start + 1 : end]
    depth = 0
    kept = []
    replace = {"SUMMARY", "DESCRIPTION", "DUE", "DTSTART", "DTEND", "LAST-MODIFIED"}
    for line in block:
        key = line.split(":", 1)[0].split(";", 1)[0].upper()
        if depth == 0 and key in ("RRULE", "RECURRENCE-ID"):
            raise NextcloudError("Recurring items must be edited in Nextcloud.")
        if depth == 0 and key in replace:
            continue
        kept.append(line)
        if line.upper().startswith("BEGIN:"):
            depth += 1
        elif line.upper().startswith("END:"):
            depth -= 1
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    lines[start + 1 : end] = kept + fields + ["LAST-MODIFIED:" + stamp]
    return serialize_ical(lines).decode("utf-8")


def components(ics):
    lines = []
    for line in ics.splitlines():
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    stack = []
    found = []
    for line in lines:
        if line.startswith("BEGIN:"):
            name = line[6:].upper()
            stack.append((name, {}))
        elif line.startswith("END:"):
            if not stack:
                continue
            name, props = stack.pop()
            if name in ("VEVENT", "VTODO"):
                found.append((name, props))
        elif stack and stack[-1][0] in ("VEVENT", "VTODO") and ":" in line:
            head, value = line.split(":", 1)
            name, *options = head.split(";")
            params = dict(option.split("=", 1) for option in options if "=" in option)
            stack[-1][1].setdefault(name.upper(), []).append((params, value))
    return found


def first(props, key):
    return props.get(key, [({}, "")])[0]


def text_value(value):
    return (
        value.replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
    )


def date_value(field, local_zone):
    params, value = field
    if not value:
        return None, False
    if params.get("VALUE") == "DATE" or (len(value) == 8 and value.isdigit()):
        return datetime.strptime(value[:8], "%Y%m%d").replace(tzinfo=local_zone), True
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC), False
    zone = local_zone
    if params.get("TZID"):
        try:
            zone = ZoneInfo(params["TZID"].strip('"'))
        except (KeyError, ValueError):
            pass
    return datetime.strptime(value, "%Y%m%dT%H%M%S").replace(tzinfo=zone), False


def events_from(entries, collection, start, end, local_zone):
    results = []
    for href, etag, ics in entries:
        records = [props for kind, props in components(ics) if kind == "VEVENT"]
        overrides = {}
        for props in records:
            if "RECURRENCE-ID" in props:
                recurrence_id, _ = date_value(first(props, "RECURRENCE-ID"), local_zone)
                if recurrence_id:
                    overrides[recurrence_id.isoformat()] = props
        for props in records:
            if "RECURRENCE-ID" in props or first(props, "STATUS")[1].upper() == "CANCELLED":
                continue
            begins, all_day = date_value(first(props, "DTSTART"), local_zone)
            if not begins:
                continue
            finishes, _ = date_value(first(props, "DTEND"), local_zone)
            duration = (
                finishes - begins
                if finishes
                else timedelta(days=1)
                if all_day
                else timedelta(hours=1)
            )
            if duration <= timedelta(0):
                duration = timedelta(days=1) if all_day else timedelta(hours=1)
            occurrences = [begins]
            rule = first(props, "RRULE")[1]
            if rule:
                try:
                    occurrences = rrulestr(rule, dtstart=begins).between(
                        start - duration, end, inc=True
                    )
                except ValueError:
                    occurrences = [begins]
            excluded = set()
            for field in props.get("EXDATE", []):
                for value in field[1].split(","):
                    excluded_date, _ = date_value((field[0], value), local_zone)
                    if excluded_date:
                        excluded.add(excluded_date.isoformat())
            for occurrence in occurrences:
                override = overrides.pop(occurrence.isoformat(), None)
                if occurrence.isoformat() in excluded and override is None:
                    continue
                if override and first(override, "STATUS")[1].upper() == "CANCELLED":
                    continue
                source = override or props
                actual_start, actual_all_day = (
                    date_value(first(source, "DTSTART"), local_zone)
                    if override
                    else (occurrence, all_day)
                )
                actual_end, _ = (
                    date_value(first(source, "DTEND"), local_zone)
                    if override
                    else (occurrence + duration, all_day)
                )
                if actual_end is None:
                    actual_end = actual_start + duration
                if actual_start < end and actual_end > start:
                    results.append(
                        {
                            "summary": text_value(first(source, "SUMMARY")[1]) or "Untitled event",
                            "start": actual_start.isoformat(),
                            "end": actual_end.isoformat(),
                            "date": actual_start.astimezone(local_zone).date().isoformat(),
                            "last_date": (actual_end - timedelta(microseconds=1))
                            .astimezone(local_zone)
                            .date()
                            .isoformat(),
                            "all_day": actual_all_day,
                            "calendar": collection["name"],
                            "calendar_slug": collection.get("slug", ""),
                            "href": href,
                            "etag": etag,
                            "description": text_value(first(source, "DESCRIPTION")[1]),
                            "editable": bool(collection.get("writable")) and not bool(rule),
                        }
                    )
    return results


def tasks_from(entries, collection, local_zone):
    results = []
    today = datetime.now(local_zone).date()
    for href, etag, ics in entries:
        for kind, props in components(ics):
            if kind != "VTODO" or first(props, "STATUS")[1].upper() in ("COMPLETED", "CANCELLED"):
                continue
            if first(props, "PERCENT-COMPLETE")[1] == "100":
                continue
            due, all_day = date_value(first(props, "DUE"), local_zone)
            recurring = bool(first(props, "RRULE")[1])
            if recurring and (not due or due.astimezone(local_zone).date() > today):
                continue
            results.append(
                {
                    "summary": text_value(first(props, "SUMMARY")[1]) or "Untitled task",
                    "due": due.astimezone(local_zone).date().isoformat() if due else "",
                    "due_at": due.isoformat() if due and not all_day else "",
                    "list": collection["name"],
                    "list_slug": collection.get("slug", ""),
                    "description": text_value(first(props, "DESCRIPTION")[1]),
                    "href": href,
                    "etag": etag,
                    "recurring": recurring,
                    "actionable": not recurring and bool(collection.get("writable", True)),
                    "editable": not recurring and bool(collection.get("writable", True)),
                }
            )
    return results


def snapshot(config, *, start=None, end=None, opener=None):
    client = Client(config, opener=opener)
    local_zone = datetime.now().astimezone().tzinfo
    today = date.today()
    current_window = (today - timedelta(days=7), today + timedelta(days=60))
    target_window = (
        (date.fromisoformat(start), date.fromisoformat(end)) if start and end else current_window
    )
    if target_window[1] <= target_window[0] or (target_window[1] - target_window[0]).days > 180:
        raise NextcloudError("The calendar date range is invalid.")
    combined = (min(current_window[0], target_window[0]), max(current_window[1], target_window[1]))
    windows = (
        [combined] if (combined[1] - combined[0]).days <= 180 else [current_window, target_window]
    )
    calendar_selection = config.get("calendars")
    task_selection = config.get("task_lists")
    if calendar_selection is not None and not isinstance(calendar_selection, list):
        raise NextcloudError("nextcloud.calendars must be a list or omitted.")
    if task_selection is not None and not isinstance(task_selection, list):
        raise NextcloudError("nextcloud.task_lists must be a list or omitted.")

    def chosen(collection, selection):
        return (
            selection is None or collection["slug"] in selection or collection["name"] in selection
        )

    events, tasks = [], []
    collections = client.propfind()
    for collection in collections:
        if "VEVENT" in collection["components"] and chosen(collection, calendar_selection):
            for range_start, range_end in windows:
                lower = datetime.combine(range_start, datetime.min.time(), tzinfo=local_zone)
                upper = datetime.combine(range_end, datetime.min.time(), tzinfo=local_zone)
                query_start = (lower - timedelta(days=1)).astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
                query_end = (upper + timedelta(days=1)).astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
                entries = client.report(collection, "VEVENT", query_start, query_end)
                events.extend(events_from(entries, collection, lower, upper, local_zone))
        if "VTODO" in collection["components"] and chosen(collection, task_selection):
            entries = client.report(collection, "VTODO")
            tasks.extend(tasks_from(entries, collection, local_zone))
    events = list({(event["href"], event["start"]): event for event in events}.values())
    events.sort(key=lambda event: event["start"])
    tasks.sort(key=lambda task: (task["due"] == "", task["due"], task["summary"].casefold()))
    return {
        "calendars": [
            {
                "name": item["name"],
                "slug": item["slug"],
                "components": sorted(item["components"]),
                "writable": item.get("writable", False),
                "events_enabled": chosen(item, calendar_selection),
                "tasks_enabled": chosen(item, task_selection),
            }
            for item in collections
        ],
        "events": events[:300],
        "tasks": tasks,
        "task_count": len(tasks),
    }
