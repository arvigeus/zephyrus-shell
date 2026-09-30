# Weather, calendar, and attention

The center panel shows weather on the left, a navigable calendar in the middle,
and Attention on the right. The columns have equal width. At narrower widths,
Weather, Calendar, and Attention become pages selected from a compact tab row.
Only the Attention feed scrolls; its heading and Priority/All tabs stay visible.
Click outside the panel or press Escape to close it. Month and year have separate
navigation arrows.
Attention has **Priority** and **All** views. Priority shows tasks due in the next
seven days, the next two events, and the two newest notifications. All shows the
open tasks, upcoming events, and local notifications. Future recurring tasks are
withheld until due. The trash icon next to Notifications dismisses only
notifications. Task checkboxes update Nextcloud.

The plus beside Tasks opens a task editor; selecting a task opens the same editor
with its details. The plus beside the selected calendar date creates an event on
that day, and selecting an event opens its details. New entries can use writable
calendars or task lists permitted by the configuration. Existing entries stay in
their original collection. All-day event end dates are inclusive in the form.
Recurring items and read-only calendars can be viewed but are edited in Nextcloud.

The component preview and live shell use Open-Meteo weather and Nextcloud CalDAV
calendars and task lists. Notifications remain local
to the running shell and are capped at 100.

## Configuration

Copy `attention/attention.example.json` to
`$XDG_CONFIG_HOME/zephyrus-shell/attention.json` (normally
`~/.config/zephyrus-shell/attention.json`). The weather location needs its name,
latitude, longitude, and IANA timezone. The KDE weather location ID is not an
Open-Meteo coordinate; for Ha Long (`VN1580410`), the coordinates are
`20.95045, 107.07336`.

The shared account lives in `zephyrus-shell/nextcloud.json`, with private DAV and
Music credential references. See [Nextcloud setup and migration](nextcloud.md).
Attention owns only calendar/task selection in `attention.json`:

```json
"calendar": {"calendars": ["Personal", "finance"], "task_lists": ["Tasks"]}
```

Omit `calendar.calendars` to show all discovered event calendars and omit
`calendar.task_lists` to show all task lists. Select by display name or CalDAV
slug; empty arrays select none. Collection names are discovered from
`/remote.php/dav/calendars/<username>/`. Run `python3 scripts/migrate-nextcloud.py`
to move existing account settings and loose credentials while preserving filters.

Weather refreshes every 15 minutes and keeps a saved forecast for offline use.
The large reading shows current model conditions, with humidity, feels-like
temperature and wind directly underneath. Beside it, six upcoming hours show local
time, condition, temperature and precipitation probability; on narrow panels this
list moves underneath.

Daily icons and hover descriptions summarize the full local day's hourly forecast
in `attention/weather.py`, independently of the six-hour list. Daylight hours define
the prevailing sky; all hours contribute rain, snow and storm information. A sunny
day can therefore say “Mostly sunny, with drizzle in the afternoon”; a rainy day
can mention sunny or dry breaks. Brief thunderstorms, freezing rain and snow take
priority in the description. These are deterministic summaries of modeled weather
codes, not observations or precipitation-probability estimates. With fewer than 18
valid hours or no daylight information, use the provider's daily condition instead.
Saved older forecasts remain usable offline until a successful refresh.
Nextcloud refreshes every 15 minutes while the panel is open. An in-memory snapshot
avoids a new request when the panel is reopened soon after closing. A private cache under
`$XDG_CACHE_HOME/zephyrus-shell/` makes repeat openings immediate; stale data is
labeled while it refreshes. Failed refreshes back off for five minutes. The refresh
icons fetch fresh data manually. Navigating
to another month fetches that month as well as the current upcoming window.

Completing or editing a nonrecurring item uses its CalDAV ETag to avoid overwriting
changes made elsewhere. Creation uses a new calendar object. Notification
dismissal never completes a task or changes a calendar event. Pending task writes
are not queued while offline.

Weather API: [Open-Meteo forecast](https://open-meteo.com/en/docs).
Calendar protocol: [Nextcloud CalDAV endpoint](https://docs.nextcloud.com/server/stable/admin_manual/issues/general_troubleshooting.html#service-discovery)
and [SabreDAV client operations](https://sabre.io/dav/building-a-caldav-client/).
