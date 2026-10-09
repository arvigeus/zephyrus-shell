# Performance, architecture and operations review

Reviewed 2026-10-10 against `9ea023a`. The cleanup makes module lifetime explicit,
removes idle work, and fixes native keyboard delivery through the shell's surface
ownership. Changes are in the working tree; the running desktop was not reloaded.

## Findings and fixes

| Finding | Cause | Result |
| --- | --- | --- |
| Module state disappeared on navigation or background completion | Lifetime depended on every feature correctly reporting a retention request | Open modules survive Desktop, Escape, navigation and successful external launches. The Spaces sidebar X or `host.close()` destroys the owning instance. |
| Escape could leave the native application without keyboard input | The persistent bar and module were separate exclusive keyboard surfaces; dismissal changed interactivity while a surface stayed mapped | One transient interaction window owns both pills and module input. Dismissal unmaps it; the passive desktop bar never requests keyboard focus. |
| Empty activity appeared when entering a module | Initial job-status loading was treated as background work and unconditionally opened the activity popup | Popups open only for actual jobs or retryable activity. Empty Activity buttons are disabled; dismissing all finished jobs closes the popup. |
| Retained modules incurred unnecessary idle requests | Files polled editing sessions every second; torrent monitoring ran even with an idle hidden module | Files polls only while editing sessions need monitoring. Hidden idle torrent monitoring pauses and refreshes on return; active downloads continue in the background. |
| Generic controls pulled native app-icon dependencies into portable QML | The default `Action` content statically referenced `AppIcon` even for text/Lucide controls | Brand artwork loads through `AppIcon` only when requested. Bundled Lucide interface icons and real application icons preserve their existing behavior. |
| Repository checks failed before the cleanup | Five Ruff violations, inconsistent Python formatting, and the eager icon import causing portable QML compilation failures | Imports, strict tuple pairing and formatting are repaired. The full lint, type, test and smoke suite passes. |

`ShellState` remains the single writer of running IDs and monitor ownership.
Removing retention requests also removes terminal submitted-command tracking,
playback retention signals, and feature-specific lifetime calculations. Host API
version 2 documents this contract. Hidden controls are disabled, while owned
players, workers and terminal sessions keep their objects. Explicitly closing a
hidden module cannot dismiss another module or its drawer.

The shared asynchronous loader still waits for drawers to finish closing. Its
visual host keeps full-screen geometry while hidden: native testing found that a
42 px desktop popup could otherwise resize retained module content to a negative
height. Monitor removal reparents the shared loader without rebuilding modules.

Keeping opened modules alive intentionally retains their memory and owned
processes. Close unused entries with the sidebar X to release them. This policy
does not retain unopened modules, and job completion has no authority to destroy
the module that owns it.

## Native focus evidence

`python3 scripts/check-focus.py` creates its own nested Hyprland compositor and
temporary XDG paths, runs the production `ShellScreen` and module loader, and
injects real Wayland keyboard events. The target application is moved onto the
same output before testing; a different output would miss the original failure.

The original sources fail with `Escape stranded native keyboard focus`. The
corrected sources pass module typing, three Escape/return cycles, preserved
search text and object identity, drawer and popup Escape, explicit stop, and
keyboard delivery back to the native application. The test also checks hidden
module geometry while a desktop popup is open.

`python3 scripts/check-focus.py --window-controls` passes actual Qt window focus,
delayed exclusive-layer release, 25/50/75/100% window sizes, floating and tiled
transitions, popups, monitor transfer/removal and module migration. Both runners
terminate their own clients and compositor even when a check fails.

The existing bounded compositor-state wait in `WindowActivation.js` remains for
explicit window actions that may overlap a drawer animation or an independent
exclusive surface. The native window-control test reproduces that overlap.
Escape restoration now follows surface unmapping and uses no activation retry.
The input-language transition remains a separate input-method behavior.

Follow-up: opening a module removes the bar's 42 px reservation and moves tiled
windows upward; the native geometry probe reproduces a y-coordinate change from
63 to 21 and a height change from 716 to 758. The transient module window has
four anchors, which cannot supply an edge reservation under the
[PanelWindow contract](https://quickshell.org/docs/v0.3.1/types/Quickshell/PanelWindow/).
Keeping the existing passive bar mapped and making the interaction surface
ignore reservations stabilizes geometry, but repeatedly fails keyboard-focus
restoration after a desktop popup. A stable popup parent did not fix that failure.
The experiment was discarded, preserving the reviewed focus behavior. The
movement remains an open issue; the user asked to avoid a more complex fix.

## Measurements

The fixed production workload covers window ordering, Spaces search, a 300-entry
Applications catalogue, repeated explicit close/reopen, and process-group
resources. Its explicit close action was established before collecting the
baseline and kept fixed during comparisons. Normal measurements use five
independent process launches; profiler runs are kept separate.

Five-run medians were 187 → 184 ms for the first Applications opening,
156 → 151 ms for later openings and 220.90 → 219.50 MiB for its process-group
RSS. The initial Applications-query comparison regressed from 10.43 to 11.68 ms.
An immediate original/final repeat measured 12.20 → 12.39 ms with overlapping
raw ranges; opening and RSS results also varied. Treat overall latency and memory
as tied. The changes are kept for correctness, dependency isolation and removal
of demonstrable idle work. Explicit Close releases all Python workers.

The experiment log in [performance.md](performance.md) records the fixed workload,
raw reports, intermediate results, repeated comparison and keep decisions.

Offscreen software measurements describe this workload, rather than full desktop
idle usage. The native checks establish input delivery and lifecycle behavior;
physical monitor hotplug, input methods, GPU frame pacing, power consumption and
configured provider latency need separate desktop measurements.

## Verification and architectural boundaries

The final `make check` passes Ruff lint/format, ty, 610 Python tests, 53 portable
QML tests, 20 JavaScript tests, backend performance budgets and all 24 smoke
scripts. Media verification uses `bash scripts/check-media.sh`; resource tests
exercise real module hosts, worker entry points and explicit teardown. Native
focus and window controls pass separately from the offscreen suite.

Owned worker infrastructure, atomic storage, provider identity/generation guards,
lazy module creation and the fixed registry remain useful boundaries. Catalogue
providers, personal records and pagination belong to their feature backends;
the shell handles lifetime and opaque navigation. A universal catalogue
controller would obscure those different contracts. The shared window model's
geometry fallback still covers compositor messages without an ordering event;
removing it needs native resize/layout performance evidence.

The baseline formatter violations account for the Python-only formatting changes
across provider and test files. The functional backend change is strict pairing
in theme contrast calculation; provider protocols and persisted data formats are
unchanged by this cleanup.
