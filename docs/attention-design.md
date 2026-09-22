# Calendar + attention

The center panel is a compact two-column layout: calendar on the left, attention
on the right. At narrow widths it stacks. The list has its own scrolling viewport;
empty notification history no longer stretches the panel to the desktop height.

For Nextcloud, use one visual inbox with two distinct item types:

- **Tasks** pinned above notifications, preferably due/overdue and explicitly
  pinned tasks rather than the entire backlog. Show a checkbox, due date and source.
- **Notifications** below, newest first, with dismiss and application actions.

Task completion must update its provider; notification dismissal only dismisses
the local notification. “Clear notifications” must never complete or delete tasks.
For large task lists, show a few pinned items plus “All tasks” so notifications
remain accessible. A dismissed reminder should not silently complete its task.

Nextcloud Tasks exposes tasks over CalDAV (VTODO). A future independent provider
should own synchronization, credentials via a secret store, offline cached tasks,
pending writes and conflict handling. The panel should consume normalized items
without owning that network logic. Credentials and the instance URL are not
requested until implementing that provider; no Nextcloud connection is made now.

Reference: https://github.com/nextcloud/tasks#apps-which-sync-with-nextcloud-tasks-using-caldav
