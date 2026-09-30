# Architecture review — 2026-09-30

The current design is suitable for incremental desktop work. The shell owns
surfaces, navigation, and lifetime; modules own providers, workers, and feature
state. Theme compatibility, thin catalogue entry points, drawer composition,
and separate Hyprland policy are intentional boundaries worth preserving.

## Findings and implemented changes

| Category | Finding | Resolution |
| --- | --- | --- |
| Correctness/reliability | A retained module's shared host could close the foreground module. | Give every module its own host; Close, Back, and retention operate on its owner. Test hidden Close and cross-ID retention. |
| Correctness/reliability | Weather lacked a response generation guard; a failed calendar fetch labeled the old snapshot with the requested month. | Ignore older weather replies and stamp calendar month only with a returned snapshot. |
| Actual duplication | Music and Radio repeated runtime socket paths, validation, JSON framing, and cleanup; Music also repeated command/property transport. | One `services/mpv.py` transport, with separate module namespaces and original timeouts. Providers, commands, player processes, and playback state remain module-owned. |
| Poor ownership | Registry reload rewrote lifecycle maps owned by ShellState. Monitor loader activation was repeated in production and a harness. | Reconcile installed IDs through ShellState and gate monitor ownership in ModuleLoader. |
| Hidden coupling | ShellState and ModuleOverlay knew media title kinds, module IDs, and `openTitle`. | Carry opaque navigation payloads; Media chooses its destination and handles its own title payload. |
| Duplicated state ownership | Attention assigned both view properties and its shared snapshot, breaking bindings after the first update. | Views use read-only bindings; responses write only the passive snapshot. Loading/generation/editor state remains local. |
| Inconsistent module/testing patterns | Apps tested a direct overlay, an undefined load flag, and forced loader destruction. Preview set a plugin ID without registering it as running, so its Apps capture could show a loading placeholder. | Exercise ModuleLoader and ShellState actions; inspect the actual content loader and capture the real Apps entry point. |
| Reliability of validation | Preview/Wayland scripts accepted process exit alone, even if QML exceptions occurred. | Require successful captures/completion markers and reject QML runtime failures. |
| Maintenance/testing | Books' old framing and generation helpers existed only for their own tests; Radio retained an unused worker path. | Remove both obsolete paths; test framing, supersession, and ordered mutations in the shared production worker. |
| Optional cleanup | Some files and small adapters are similar or large. | Keep domain-specific adapters and controllers; file size alone does not justify extraction. |

New rules and ownership details are in [architecture.md](architecture.md) and
[plugins.md](plugins.md), with contributor reminders in `AGENTS.md`.

## Deliberately deferred

- **Monitor removal:** retained modules are pinned by screen name. Removing that
  screen destroys its surface, but there is no policy to relocate the module or
  reconcile its running/retention records. Choose stop versus migration, then
  implement it against real hotplug behavior. Logical two-owner smoke checks do
  not validate physical hotplug.
- **Shared Nextcloud integration:** the panel owns the worker; `AttentionData` is
  only a passive last snapshot, and the disk cache holds one range. A second
  consumer needs a single integration owner, explicit range/cache identities,
  and a decision about writes surviving panel closure. Reads and writes use
  separate worker lanes: an older in-flight snapshot can finish after a mutation
  invalidates the disk cache. Guard backend cache publication against mutation
  generations as part of that work; frontend generation checks alone cannot
  protect it. Do not copy AttentionPanel's request/cache logic into new views.
- **Local library/import services:** Books, Games, and Music intentionally use
  shared local-library and torrent components currently located under `media/`.
  This is a cross-catalogue dependency, not a shell-host dependency. A future
  local-library extraction must preserve the SQLite schema, record identities,
  import/move semantics, and existing XDG paths together. Moving files alone
  would obscure rather than improve that boundary.
- **Terminal retention:** command submission retains the terminal until explicit
  close; it does not detect when a foreground command ends. A terminal is an
  interactive session, so automatic release needs a deliberate UX decision and
  session events. Projects' managed operations instead end with their module.
- **Catalogue controllers and persistence:** Books, Games, Media, Music, and
  Radio have different identity, paging, offline, and playback semantics. Shared
  controls/model reconciliation and owned workers already cover the stable
  common responsibilities. Keep feature logic local until another concrete
  duplication justifies extraction.
- **XDG migration:** Python call sites vary in how they treat empty environment
  values, and legacy favorites/cache locations differ by module. Unify semantics
  only with an explicit compatibility/migration plan. The unused misspelled
  `media/media.exampe.json` also merits separate configuration cleanup; the
  documented sample remains `media/media.example.json`.

## Validation and manual follow-up

The review ran the README Python suite, portable QML tests, both Node suites,
Hyprland configuration parser, preview, Apps, Media, Books, Games, general module,
retained/state, performance, and current-desktop Wayland checks. Python HTTP
fixtures and private D-Bus smoke sessions require execution outside the restricted
sandbox. Preview generated all twelve captures. Provider smoke tests primarily
use fixtures and isolated XDG directories; preview uses configured live data.

Before desktop UX/session changes, manually verify drawer exit/focus and Escape
in Hyprland, retained playback and explicit Close on two physical monitors,
monitor unplug/replug, terminal session cleanup, and actual Music/Radio playback
controls/metadata. Before shared Nextcloud work, verify failed month changes,
refresh overlapping a mutation, ETag conflicts, and closure during a write with
an isolated test account. Configuration parsing and a Wayland harness do not
prove these behaviors. No hardware action, GPU/power measurement, or live
Hyprland input behavior is claimed here.
