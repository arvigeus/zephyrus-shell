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

The `nextcloud.url` is the instance base URL, and `nextcloud.username` is the login
name. Generate a dedicated app password in Nextcloud Personal settings → Security.
Save it in the file named by `nextcloud.password_file` with mode `0600`; keep it out
of this repository. The shell reads the file but never writes or logs the password.
For example:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell"
read -rsp 'Nextcloud app password: ' nc_pass
printf '%s' "$nc_pass" > "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/nextcloud-app-password"
unset nc_pass
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/nextcloud-app-password"
```

Omit `nextcloud.calendars` to show **all** discovered event calendars. To select
specific ones, add an array of their display names or CalDAV slugs, for example
`"calendars": ["Personal", "finance"]`. Likewise, omit `nextcloud.task_lists`
to include all task lists, or provide an array to filter them. Calendar and task
list names are discovered from `/remote.php/dav/calendars/<username>/`.

Weather refreshes every 15 minutes and keeps a saved forecast for offline use.
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
