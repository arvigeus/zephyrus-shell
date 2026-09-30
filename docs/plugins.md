# A space is a directory

Copy `templates/plugin/` into `plugins/your-name/`. Change the manifest's `id` and
`name`, then press **Reload spaces** in the left drawer. You do not edit shell code.

```json
{
  "apiVersion": 1,
  "id": "books",
  "name": "Books",
  "icon": "monitor",
  "order": 40,
  "entry": "Main.qml",
  "enabled": true
}
```

IDs use lowercase letters, digits and hyphens, beginning with a letter. `order` is
an integer. `entry` must resolve inside the plugin directory to an existing QML
file. Set `enabled` to false or remove the directory and reload to remove a space.
Modules can request to remain open through `host.requestKeepRunning(id, true)`.
Without a request, selecting Desktop or another module destroys the current
module. Call `host.requestKeepRunning(id, false)` when the background work ends.
The Spaces drawer gives retained modules a Close button. Escape and
`host.close()` stop the selected module. Older `keepRunning` manifest values
remain accepted but no longer retain a module automatically.
Invalid manifests produce visible errors without stopping other entries.

## The entire host contract

Your root is a QtQuick Item (ColumnLayout, Rectangle, FocusScope, etc.). Declare
`property var host`. The shell assigns it after creating the component:

- `host.apiVersion`: currently 1.
- `host.close()`: destroys this plugin, including while retained behind another space.
- `host.back()`: destroys this plugin and returns to the space list when selected;
  a hidden plugin stops without changing the foreground space.
- `host.requestKeepRunning(id, enabled)`: retain this module while hidden, or
  release it when background work ends. Pass the module's manifest ID.
- `host.openPlugin(id, payload)`: open an installed module; returns false if the
  destination is unavailable. The optional payload is opaque to the shell.
- Optional `function handleOpen(payload)`: receives the latest navigation payload
  once the destination is loaded, has its host, and is selected. Selecting another
  space, Desktop, or closing cancels an undelivered payload. Normal activation
  without a payload does not call this function.
- Optional `function activate()`: called after host injection; focus your search field here.

The host is scoped to the module instance. Retention requests for another ID are
ignored. Keep feature-specific destination choices and payload validation inside
the participating modules; the shell must not interpret title, store, or provider
records. A destination without `handleOpen` simply opens normally.

The Loader sizes the root to the available desktop overlay area below the top pills. Import `../../widgets`
and `../../core` for shared controls and theme tokens. The included Apps plugin
is a complete working example.

## Lifetime and resource ownership

Startup and Reload read JSON only. Opening the library list does not load plugin
QML. Selecting one creates its root Item after the drawer closes. Switching
spaces destroys a module unless it requested retention. A retained module remains
alive until it releases that request, Escape, `host.close()`, or the drawer’s
Close control stops it.
Quickshell/Qt may retain compiled QML code in
their cache; the promise is no live plugin UI, timers, or owned workers while closed,
not literally zero bytes of metadata or cached code.

Put timers, models, signal Connections, and Quickshell Process objects underneath
your root. Do not create a plugin singleton or import a module with permanent
background work. Use owned Process objects for workers, never detached execution;
explicitly stop any external resources in Component.onDestruction when needed.
Launching a user application is intentionally detached and may survive the drawer.
Use `External.launch(command, host)` for these launches, or
`Browser.open(url, moduleId, command, host)` for browser links (`command` may be
an empty string to use the configured browser). Both close the owning module
after handing off, removing its overlay and releasing keyboard focus. Pass the
same host to nested controls that open external applications.

Persist important state to a plugin-specific XDG data directory before destruction.
State held only in QML is lost on close. Avoid polling when a service offers signals.

Plugins are trusted local QML, **not a security sandbox**. A plugin can execute code
with your account's permissions. Manifest validation is correctness checking, not
isolation. Only install code you trust.

## Reload from a terminal

```sh
quickshell -p /absolute/path/to/zephyrus-shell ipc call shell reloadPlugins
```

The directory intentionally has no persistent filesystem watcher. Changes appear
when reloaded, and normal Quickshell source hot reload handles QML edits.

## Presentation and icons

The Spaces drawer lists Desktop and the installed modules. Selecting one closes the drawer and opens
a full desktop overlay behind the pills, with content starting below the 46 px
pill bar. The pills remain visible and clickable. The host has no heading or
navigation buttons: Escape closes the visible module; Desktop hides it while
the module has an active retention request.

The default background is translucent. A module may declare
`property url backgroundImage: Qt.resolvedUrl("background.jpg")` on its root.
The host crops this image to fill the desktop over an opaque base, so the desktop
does not show through, even if the image has alpha or fails to load. Omit the
property (or set it to an empty URL) to use the default background.

Use Lucide for interface icons: `widgets/Icon.qml` or `Action.iconName`. Manifest
`icon` is a bundled name from `assets/lucide/`, without `.svg` (for example,
`monitor`). Unknown values fall back to `monitor`. Add official
Lucide SVG assets when a new icon is needed; do not use emoji or text glyphs as
interface icons. Application and brand artwork can retain their native icons.

Module creation waits for the drawer exit animation and uses an asynchronous
Loader with a shared loading indicator. Escape cancels loading; Desktop hides
retained modules while their initialization finishes.
Module content is destroyed on close, including when creation is in progress.
