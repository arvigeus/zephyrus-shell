# Built-in spaces

This is a personal shell with a fixed set of modules. There is no runtime plugin
scan, manifest format, registration process, or reload button.

To add a space:

1. Add its entry point under `plugins/<id>/Main.qml`.
2. Add `{id, name, icon}` to `core/Modules.qml` in drawer order. `icon` is a bundled
   Lucide name without `.svg`.
3. Import the entry point by an alias in `shell/ModuleOverlay.qml`, declare its
   `Component`, and add it to the component map.
4. Exercise the real entry point through `ShellState.openPlugin(id)` in a smoke
   harness. Restart the shell to pick up the source change.

The components are known at compile time. Their instances, native resources and
workers remain lazy. Creation waits for drawers to close and uses the shared
asynchronous loader. Escape cancels loading or closes the active module.

## Host contract

Every root exposes `property var host`. Its host belongs to that instance:

- `host.close()` stops that instance, including when hidden.
- `host.back()` stops it and opens Spaces when it is the foreground module.
- `host.requestKeepRunning(id, enabled)` retains only its own ID while background
  work continues. Release it when that work ends.
- `host.openPlugin(id, payload)` validates the destination and opens it. The
  destination's optional `handleOpen(payload)` interprets the opaque payload.
- An optional `activate()` method restores focus when the module becomes visible.

Selecting Desktop or another space destroys modules without a retention request.
Retained instances keep their owned workers and playback. Explicit Close and
Escape always stop the selected module. Lifecycle records live in
`core/ShellState.qml`; loading, hosts, and payload delivery live in
`shell/ModuleOverlay.qml`.

The overlay extends behind the 42 px bar. Content begins below it without a
shared heading or navigation controls. Backgrounds default to translucent. An
optional root `property url backgroundImage` supplies an opaque image background;
`backgroundImageOpacity` and `backgroundImageWidth` tune its display and decoding.

Workers belong to module instances. Use `services/Worker.qml` for JSON-lines
backends. Set `startOnDemand: true` for services only used by optional actions;
requests are buffered until startup and settle on reply, timeout, or exit. Do not
make optional module services core singletons. Register ordered mutations and
superseded reads through `services.worker.serve` in the backend.

Check lifecycle changes with `bash scripts/check-workers.sh`,
`bash scripts/check-modules.sh`, and `bash scripts/check-retained.sh`.
