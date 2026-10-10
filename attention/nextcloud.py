"""Nextcloud CalDAV: discover collections, read events and tasks, write simple items."""

import re
import xml.etree.ElementTree as ET
from datetime import UTC, date, datetime, timedelta
from urllib.parse import quote, unquote, urljoin
from uuid import uuid4
from zoneinfo import ZoneInfo

from dateutil import tz
from dateutil.rrule import rrulestr

from services.nextcloud import DAVClient, NextcloudError

DAV = "DAV:"
CAL = "urn:ietf:params:xml:ns:caldav"
NS = {"d": DAV, "c": CAL}


class Client(DAVClient):
    def __init__(self, config, *, opener=None):
        scope = "remote.php/dav/calendars/" + quote(config.get("username", ""), safe="") + "/"
        super().__init__(config, scope=scope, opener=opener)

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

    def rewrite(self, href, etag, kind, fields, replace):
        """Replace properties of a single-component item, guarded by its ETag."""
        if not href or not etag:
            raise NextcloudError("This item cannot be updated. Refresh and try again.")
        raw, headers = self.request("GET", href)
        if headers.get("ETag") != etag:
            raise NextcloudError("This item changed on Nextcloud. Refresh and try again.")
        data = raw.decode("utf-8")
        due_line = next((field for field in fields if field.startswith("DUE")), None)
        if due_line:
            local_zone = tz.gettz()
            existing = next((props for name, props in components(data) if name == kind), {})
            due, _ = date_value(first(existing, "DUE"), local_zone)
            if due and due_line.endswith(":" + due.astimezone(local_zone).strftime("%Y%m%d")):
                # The form edits dates only; keep an unchanged due date's time of day.
                fields = [field for field in fields if field != due_line]
                replace = replace - {"DUE"}
        self.request(
            "PUT",
            href,
            update_ical(data, kind, fields, replace | {"LAST-MODIFIED"}),
            {"Content-Type": "text/calendar; charset=utf-8", "If-Match": etag},
        )

    def complete_task(self, task):
        stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
        self.rewrite(
            str(task.get("href", "")),
            str(task.get("etag", "")),
            "VTODO",
            ["STATUS:COMPLETED", "PERCENT-COMPLETE:100", "COMPLETED:" + stamp],
            {"STATUS", "PERCENT-COMPLETE", "COMPLETED"},
        )

    def save_item(self, config, kind, entry):
        if kind not in ("VTODO", "VEVENT") or not isinstance(entry, dict):
            raise NextcloudError("The calendar item is invalid.")
        slug = str(entry.get("collection", ""))
        selected = selection(config, "task_lists" if kind == "VTODO" else "calendars")
        collection = next(
            (
                item
                for item in self.propfind()
                if item["slug"] == slug
                and kind in item["components"]
                and item["writable"]
                and chosen(item, selected)
            ),
            None,
        )
        if collection is None:
            raise NextcloudError("Choose a writable calendar or task list.")
        fields = entry_fields(kind, entry)
        href = str(entry.get("href", ""))
        if href:
            if not href.startswith(collection["url"]):
                raise NextcloudError("This item cannot be updated. Refresh and try again.")
            replace = (
                {"SUMMARY", "DESCRIPTION", "DUE"}
                | ({"DURATION"} if any(field.startswith("DUE") for field in fields) else set())
                if kind == "VTODO"
                else {"SUMMARY", "DESCRIPTION", "DTSTART", "DTEND", "DURATION"}
            )
            self.rewrite(href, str(entry.get("etag", "")), kind, fields, replace)
            return {"saved": True}
        identity = uuid4().hex
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
            collection["url"] + identity + ".ics",
            serialize_ical(lines),
            {"Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*"},
        )
        return {"saved": True}


def selection(config, key):
    value = config.get(key)
    if value is not None and not isinstance(value, list):
        raise NextcloudError(f"calendar.{key} in attention.json must be a list or omitted.")
    return value


def chosen(collection, selected):
    """An omitted selection includes everything; entries match a name or CalDAV slug."""
    return selected is None or collection["slug"] in selected or collection["name"] in selected


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
            return fields
        starts = date.fromisoformat(str(entry.get("start_date", "")))
        ends = date.fromisoformat(str(entry.get("end_date", "")))
        if entry.get("all_day"):
            if ends < starts:
                raise ValueError()
            return [
                *fields,
                "DTSTART;VALUE=DATE:" + starts.strftime("%Y%m%d"),
                "DTEND;VALUE=DATE:" + (ends + timedelta(days=1)).strftime("%Y%m%d"),
            ]
        # Naive astimezone() applies the local zone's offset for that date, DST included.
        start_at = datetime.combine(
            starts, datetime.strptime(str(entry.get("start_time", "")), "%H:%M").time()
        ).astimezone()
        end_at = datetime.combine(
            ends, datetime.strptime(str(entry.get("end_time", "")), "%H:%M").time()
        ).astimezone()
        if end_at <= start_at:
            raise ValueError()
        return [
            *fields,
            "DTSTART:" + start_at.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ"),
            "DTEND:" + end_at.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ"),
        ]
    except (ValueError, OverflowError) as error:
        raise NextcloudError(
            "Check the date and time. Use YYYY-MM-DD and HH:MM, with the end after the start."
        ) from error


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


def update_ical(data, kind, fields, replace):
    """Drop the component's top-level `replace` properties and append `fields`."""
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
    depth = 0
    kept = []
    for line in lines[start + 1 : end]:
        key = line.split(":", 1)[0].split(";", 1)[0].upper()
        if depth == 0 and key in ("RRULE", "RECURRENCE-ID"):
            raise NextcloudError("Recurring items must be edited in Nextcloud.")
        if depth == 0 and key in replace:
            continue
        kept.append(line)
        if key == "BEGIN":
            depth += 1
        elif key == "END":
            depth -= 1
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    lines[start + 1 : end] = [*kept, *fields, "LAST-MODIFIED:" + stamp]
    return serialize_ical(lines)


def components(ics):
    """Return (name, {PROPERTY: [(params, value)]}) for each VEVENT and VTODO."""
    stack = []
    found = []
    for line in unfold_ical(ics):
        if line.startswith("BEGIN:"):
            stack.append((line[6:].upper(), {}))
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
    # One pass, so an escaped backslash followed by "n" stays literal.
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m[1] in "nN" else m[1], value)


def cancelled(props):
    return first(props, "STATUS")[1].upper() == "CANCELLED"


def date_value(field, local_zone):
    """Parse a DATE or DATE-TIME property; returns (aware datetime | None, is_date)."""
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


def utc_until(rule, zone):
    """dateutil requires a UTC UNTIL with an aware DTSTART; RFC 5545 allows DATE/local values."""

    def convert(match):
        moment, is_date = date_value(({}, match.group(1)), zone)
        if is_date:
            moment += timedelta(days=1, seconds=-1)
        return "UNTIL=" + moment.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")

    return re.sub(r"(?i)UNTIL=([0-9]{8}(?:T[0-9]{6}Z?)?)", convert, rule)


def span(props, local_zone):
    begins, all_day = date_value(first(props, "DTSTART"), local_zone)
    if not begins:
        return None
    finishes, _ = date_value(first(props, "DTEND"), local_zone)
    default = timedelta(days=1) if all_day else timedelta(hours=1)
    duration = finishes - begins if finishes and finishes > begins else default
    return begins, duration, all_day


def events_from(entries, collection, start, end, local_zone):
    """Expand events overlapping [start, end); recurrence overrides replace their instance."""
    results = []

    def add(props, href, etag, begins, finishes, all_day, editable):
        if not (begins < end and finishes > start):
            return
        results.append(
            {
                "summary": text_value(first(props, "SUMMARY")[1]) or "Untitled event",
                "start": begins.isoformat(),
                "end": finishes.isoformat(),
                "date": begins.astimezone(local_zone).date().isoformat(),
                "last_date": (finishes - timedelta(microseconds=1))
                .astimezone(local_zone)
                .date()
                .isoformat(),
                "all_day": all_day,
                "calendar": collection["name"],
                "calendar_slug": collection.get("slug", ""),
                "href": href,
                "etag": etag,
                "description": text_value(first(props, "DESCRIPTION")[1]),
                "editable": editable,
            }
        )

    for href, etag, ics in entries:
        records = [props for kind, props in components(ics) if kind == "VEVENT"]
        overridden = set()
        for props in records:
            if "RECURRENCE-ID" not in props:
                continue
            try:
                moment, _ = date_value(first(props, "RECURRENCE-ID"), local_zone)
                parsed = span(props, local_zone)
            except ValueError:
                continue
            if moment:
                overridden.add(moment.timestamp())
            if parsed and not cancelled(props):
                begins, duration, all_day = parsed
                add(props, href, etag, begins, begins + duration, all_day, False)
        for props in records:
            if "RECURRENCE-ID" in props or cancelled(props):
                continue
            rule = first(props, "RRULE")[1]
            try:
                parsed = span(props, local_zone)
                if not parsed:
                    continue
                begins, duration, all_day = parsed
                occurrences = [begins]
                if rule:
                    expanded = rrulestr(utc_until(rule, begins.tzinfo), dtstart=begins)
                    occurrences = expanded.between(start - duration, end, inc=True)
                excluded = {
                    moment.timestamp()
                    for params, values in props.get("EXDATE", [])
                    for value in values.split(",")
                    if (moment := date_value((params, value), local_zone)[0])
                }
            except ValueError:
                continue
            editable = bool(collection.get("writable")) and not rule
            skipped = overridden | excluded
            for occurrence in occurrences:
                if occurrence.timestamp() not in skipped:
                    add(props, href, etag, occurrence, occurrence + duration, all_day, editable)
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
            try:
                due, all_day = date_value(first(props, "DUE"), local_zone)
            except ValueError:
                continue
            recurring = bool(first(props, "RRULE")[1])
            if recurring and (not due or due.astimezone(local_zone).date() > today):
                continue
            editable = not recurring and bool(collection.get("writable", True))
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
                    "actionable": editable,
                    "editable": editable,
                }
            )
    return results


def snapshot(config, *, start=None, end=None, opener=None):
    """Collections, events for the requested range plus the upcoming window, and open tasks."""
    client = Client(config, opener=opener)
    local_zone = tz.gettz()
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
    calendar_selection = selection(config, "calendars")
    task_selection = selection(config, "task_lists")

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
