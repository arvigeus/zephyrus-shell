# Interface conventions

- Use bundled Lucide SVGs through `widgets/Icon.qml` or `Action.iconName` for interface icons. Do not introduce Unicode symbols, emoji, or another icon family as interface icons. Application and brand artwork may use their own icons through `AppIcon`.
- Plugin manifest `icon` values are bundled Lucide icon names (without `.svg`).
- The Desktop drawer lists modules only. Selecting a module closes the drawer and opens its content in the shared desktop overlay below the 66 px pill bar. Keep module loading and host navigation in `shell/ModuleOverlay.qml` so all modules share this behavior.
- Plugins own their runtime resources and are destroyed when their overlay closes.

- Module backgrounds extend behind the pills; content starts below them. Do not add a shared heading or navigation buttons. Escape and Desktop close the module. Default backgrounds are translucent; optional root `property url backgroundImage` uses an opaque image background.
- Missing application icons remain blank. Application grid labels share a fixed top alignment below their icon slots.

- Both drawers are flush to their screen edges with square corners and stack above the pills. Use shared `DrawerSlide.qml` for entry/exit motion; retain content until closing animation completes.

- Defer module creation until drawers finish closing; use the shared asynchronous loader and loading state. Never show an empty-results message while initializing. Applications defaults to Favorites when any saved favorites are installed, otherwise All applications; retain per-app add/remove controls.

- Application favorite controls use an 18 px Lucide star: filled and always visible for favorites, outline on hover or keyboard focus otherwise. Preserve a 32 px click target.

- Keep the hardware snapshot between Settings openings and refresh in place; reserve logo space to avoid layout shifts. Outside-click dismissal must use a hit area disjoint from the drawer, never a global event filter. The user profile dialog must outlive the drawer and open on its own surface after the drawer closes.

## Media modules

- Movies and TV Series are separate manifests and thin entry points sharing `media/MediaBrowser.qml` and the owned `MediaService.qml` worker. Keep provider logic in `media/backend.py`, never in the shell host.
- Media secrets and provider templates live in `$XDG_CONFIG_HOME/zephyrus-shell/media.json`, not the repository or QML. The example file and `docs/media.md` describe configuration. Do not import NexFlix secrets automatically.
- Preserve IMDb/TMDB identity aliases and personal records during metadata refresh. Ignore responses from older browse/title/episode generations. Keep loading states distinct from empty results and reserve artwork geometry.
- Playback source resolution is separate from catalogue metadata, allowing future local sources. Movies have no episode controls. YouTube and local-library scanning are deferred.
- Verify media changes with Python tests and `bash scripts/check-media.sh`; the latter uses isolated XDG data and real module entry points.

- Use the documented snake_case media key names and named provider objects. IMDbApi outages must fall through to configured TMDB/OMDb capabilities; OMDb is not a discovery or backdrop provider. Preserve provider pagination tokens and use a short shared outage cooldown.

- Media uses filled split buttons for Watch online and trailers, a concise overview and a separate full Cast tab. Do not restore the Notes & URL editor. Preserve artwork ownership against late details and use `widgets/CrossfadeImage.qml` for overlapping image transitions.
