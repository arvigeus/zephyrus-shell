# Shell performance and autoresearch

Run a bounded benchmark → profile → verify → research → improve loop. The agent
does the research; the shell gains no resident agent, telemetry or monitoring
service. This adapts the experiment log and keep/discard approach from
[autoresearch](https://github.com/karpathy/autoresearch) and the
[HN discussion](https://news.ycombinator.com/item?id=49309549).

## Measurements

```sh
python3 scripts/benchmark-shell.py --output tests/artifacts/performance-before.json
# Make one change, verify it, then repeat on the same machine:
python3 scripts/benchmark-shell.py --output tests/artifacts/performance-after.json \
  --baseline tests/artifacts/performance-before.json
# Locate the expensive bindings/functions in Qt Creator's QML Profiler:
python3 scripts/benchmark-shell.py --runs 1 --output tests/artifacts/performance-profile.json \
  --profile tests/artifacts/performance.qtd
```

The runner needs Linux `/proc`, Python, Quickshell, Qt's software/offscreen
backend and `dbus-run-session`; profiling additionally needs `qmlprofiler`.
Add `--profile-features javascript,binding,creating,handlingsignal,compiling`
when investigating individual JavaScript functions; these traces can be large.
Private bus/debug sockets need permission outside a socket-restricted sandbox.
Everything runs with temporary XDG configuration, data and cache, a private
session bus, an unavailable system bus and disabled network proxies. The fixture
does not launch applications, run theme synchronization or operate session power.

`performance.qml` uses the real `SpaceSearch`, `WindowOrderModel`, `ModuleLoader`
and Applications entry point. It checks search result counts, window identity and
ordering, and releases Applications via the real explicit Close lifecycle action
(`ShellState.stopPlugin`, also used by the Spaces sidebar X). Five
process launches are the default; each includes:

- 40 geometry response batches at 8, 32 and 64 windows, timed through deferred
  publication. These stress the shared model used by every monitor's bar.
- Six query patterns, with six warmup events and 120 measured events at each of
  100, 500 and 1,000 search entries. One query per timer event allows Qt to render
  and destroy obsolete delegates. Timing covers synchronous text/model updates.
- A real 300-entry desktop catalogue, Applications grid typing, and five
  open/close cycles. Open timing includes asynchronous module loading, catalogue
  readiness and GPU discovery completion (including unavailable-service errors).
- Stable resource phases before opening Applications, with it open, and after
  closing. CPU is the shell's main process as a percentage of one CPU; memory is
  summed RSS of the private process group, including its bus and workers.
  Context switches are a scheduling proxy, not a hardware wakeup counter.
  The runner rejects workers remaining after release.

Reports preserve raw runs, medians, a workload fingerprint and hashes of the
production sources under investigation. Comparisons reject a changed QML/desktop
entry fixture, different environment or profiled data. Cold and warm openings are
reported separately; their pooled median hides initial scan costs.
Memory includes shared pages more than
once and Qt/allocator caches can remain after QObject destruction. The idle host
fixture does **not** instantiate the entire native desktop or a compositor.
Offscreen software timings do **not** establish GPU frame times, physical input
latency, monitor scaling behavior, battery consumption or provider/network latency.
Millisecond QML clocks quantize very short operations; averaged batches reduce
this effect. Short CPU samples near zero should not be interpreted as precise
percentage improvements.

Profile runs carry instrumentation overhead and cannot be compared with normal
runs. Do not run tests, builds or another benchmark concurrently with measurement.
Use the same machine, renderer, workloads and power mode; capture repeated runs
again when variability approaches the claimed improvement. Median averages
identify hotspots; inspect raw runs and the QML trace for slow cases too.

## Agent experiment protocol

1. Read `AGENTS.md`, inspect the current diff and preserve unrelated work. Run the
   baseline and correctness checks before changing production code. Set a finite
   experiment count or time window; a normal session starts with three hypotheses.
2. Profile the fixed workload. Write down the hotspot, its trigger, a hypothesis,
   the target metric and any expected memory/CPU tradeoff before editing.
3. Research the relevant primary documentation. Qt recommends
   [profiling actual bindings and JavaScript](https://doc.qt.io/qt-6/qtquick-performance.html)
   before optimization. Prefer eliminating work, bounding resource ownership and
   coalescing batches to adding caches, threads or polling.
4. Change one hypothesis at a time. Keep the benchmark workload and verifier
   fixed while comparing. Never special-case fixture names/sizes, skip readiness,
   drop results, remove animations or weaken lifecycle checks to improve a score.
5. Verify real behavior: focused QML/Node tests and the appropriate smoke scripts;
   shared worker/backend changes also need Python tests. Media changes must pass
   `bash scripts/check-media.sh`. Run `make check` on the final candidate.
6. Benchmark again without the profiler. Keep a change only if repeated results
   show a useful gain, correctness passes and resource/other latency regressions
   are understood. Prefer a simpler implementation when results are tied. Revert
   only your own rejected experiment; never reset the user's checkout.
7. Append an experiment record below with before/after measurements, verification,
   evidence and keep/discard reasoning. Stop at the session bound, or when remaining
   hotspots need native desktop evidence or gains are within measurement noise.

For native follow-up, use an isolated Hyprland compositor and the production
entry point with representative app icons, wallpapers, two monitor scales,
rapid drawer/search transitions and retained playback. Capture a QML trace and
steady idle CPU/RSS before changing compositor refresh or polling. In particular,
`WindowList`'s geometry fallback covers resize/layout messages that lack an
order event; removing it requires verifying those cases on the compositor.

The native focus regression is reproducible without operating the current shell:
`python3 scripts/check-focus.py` creates a nested compositor and drives real
Wayland keyboard events through the production `ShellScreen` and module loader.
`--window-controls` additionally exercises window sizing, activation, monitor
removal and retained module migration. These checks require a parent Wayland
session and the dependencies listed in the README; they establish native input
delivery and lifecycle correctness, rather than GPU or power performance.

## Experiment log

2026-10-05, baseline `b01ce4f`, Quickshell 0.3.1 / Qt 6.11.2,
Python 3.14.7, Linux 7.2.8-arch1-2, offscreen/software. Five independent launches
before and after, with the same QML workload and 300 desktop-entry files. Cold and
warm baseline medians were derived from its existing raw opening samples; the
workload fingerprint was attached afterward without changing the workload.

| Metric (median) | Before | After | Change |
| --- | ---: | ---: | ---: |
| 8-window response batch | 0.275 ms | 0.075 ms | −72.7% |
| 32-window response batch | 3.175 ms | 0.200 ms | −93.7% |
| 64-window response batch | 13.150 ms | 0.375 ms | −97.1% |
| Spaces query, 100 entries | 3.775 ms | 3.217 ms | −14.8% |
| Spaces query, 500 entries | 9.892 ms | 5.683 ms | −42.5% |
| Spaces query, 1,000 entries | 11.117 ms | 8.992 ms | −19.1% |
| Applications query, 300 entries | 14.592 ms | 10.658 ms | −27.0% |
| Applications first opening | 17,706 ms | 184 ms | −99.0% |
| Applications warm opening | 181.5 ms | 152.0 ms | −16.3% |
| Process-group RSS, open after rapid searches | 1,904.4 MiB | 218.1 MiB | −88.5% |
| Process-group RSS, released | 1,121.7 MiB | 186.2 MiB | −83.4% |
| Process-group RSS, idle host before Applications | 176.3 MiB | 175.8 MiB | −0.2% |
| Python workers after release | 0 | 0 | preserved |

The 64-window raw runs fell from 7.7–15.125 ms to 0.325–0.475 ms. First openings
fell from 17,355–17,929 ms to 177–187 ms. Applications query averages ranged
10.458–10.842 ms in the final five launches. Idle-host memory is effectively
unchanged. Short idle CPU/context-switch samples are near the measurement floor,
so no power-consumption or steady-desktop CPU improvement is claimed.

| Experiment | Evidence and change | Decision |
| --- | --- | --- |
| 1. Window batch sorting | The original sorting binding ran 4,167 times over 120 geometry batches. Observe client geometry/handle signals and sort once after a batch, keeping identity and unchanged-publication suppression. The next trace recorded 125 sort calls including setup/cleanup. The isolated trial measured 0.375 ms at 64 windows. | Keep: repeated final runs confirm the gain; order, replacement and removed-client checks pass. |
| 2. Search indexing | Normalize catalogue text once, normalize each query once and preserve published models when ordered results are identical. A single trial cut 500-entry Spaces queries to 5.775 ms and Applications queries to 12.725 ms. Memory alone did not reliably improve at this stage. | Keep for responsiveness: repeated results confirm the gain; ranking, multi-word input, live metadata, Favorites and keyboard controls pass. |
| 3. Catalogue publication | The completed trace recorded 305 evaluations of the Applications catalogue binding and 14,895 grid delegate/Menu creations. Desktop-entry metadata was repeatedly sorting and republishing an incomplete catalogue. Observe membership/name/visibility changes and publish one completed batch, including the initial Favorites choice. The first trial reduced first opening to 1,037 ms and open RSS to 329.3 MiB. A follow-up trace exposed observer model resets; using the existing `ScriptModel` preserves observers as entries arrive. Five runs of that refinement measured 218 ms first opening and 227.5 MiB open RSS, but Applications queries regressed to 15.533 ms. | Keep the catalogue batching and observer reuse; resolve the query regression with experiment 4 rather than hide the tradeoff. Metadata hide/restore and module/worker destruction pass. |
| 4. Lazy GPU menus | The post-batching trace still created 2,705 menus during grid changes, although no menu was opened. Declare a component factory and create the menu on first mouse/keyboard interaction, owned by its application tile. A single trial measured 10.792 ms queries, 187 ms first opening and 215.8 MiB open RSS. | Keep: five final runs confirm faster queries and both cold/warm opening, with lower memory. Real GPU picker toggling and explicit popup parent ownership pass. |

The experiment fixture was corrected before baseline collection: count expectations
now reflect multi-word matching, typing is event-paced, resource phases exclude
loading/teardown and `/proc` exit races are ignored. A truncated profiler export
was discarded. The reusable profiler attaches to Quickshell's debugger, checks
that XML export finalized and defaults to bindings/creation/signal/compilation
events to keep traces manageable. Profile timings never enter comparisons.
The finalized trace is valid XML: catalogue observer creation records fell from
92,700 with model resets to 3,000 with preserved observers, and the final grid
workload recorded zero GPU menu creations. Interactive smoke still opens and
toggles those menus and verifies their popup parent is the owning app tile.

Verification passed: Ruff lint/format, ty, 464 Python tests, 53 portable QML tests,
13 JavaScript tests, existing backend performance budgets and all 18 smoke
scripts in a successful final `make check`. The first full run exposed a metadata test attempting
to write through an unavailable DesktopEntry setter; it now exercises mutable
QObject metadata through the same production Applications entry point. The
pre-existing theme verifier expected removed Projects headings; it now checks
the real search/count controls and still verifies light/dark, font, invalid-file,
retained/recreated module and cold-session roundtrips.

Raw local reports: `tests/artifacts/performance-before.json`,
`performance-order.json`, `performance-search.json`, `performance-catalogue.json`
and `performance-after.json`; intermediate observer-reset/incremental reports,
the verification log and final `.qtd` trace are in
the same ignored artifact directory. Recreate them with the commands above.
This session ends after four production hypotheses, with the fourth added to
address the measured query regression. Native compositor/GPU measurements are
the next independent research task; the geometry fallback remains necessary
until resize/layout cases are measured there.

### 2026-10-10: module lifetime, native focus and idle work

Baseline `9ea023a`, Quickshell 0.3.1 / Qt 6.11.2, Python 3.14.7,
Linux 7.2.8-arch1-2, offscreen/software. Bound: three production hypotheses.
The explicit-close action in `performance.qml` was established before the
baseline, because Desktop now deliberately retains modules. Its workload hash
`a90afd1c4efdd48f25461ecdb81c224b46a56026a46ecb94870d4ebf968aa2bf`
and the benchmark runner were fixed throughout all comparisons. The workload
still requires correct results, catalogue readiness and zero workers after
explicit release.

Five independent launches before and after:

| Metric (median) | Before | Final |
| --- | ---: | ---: |
| 64-window response batch | 0.35 ms | 0.35 ms |
| Spaces query, 1,000 entries | 9.48 ms | 9.07 ms |
| Applications query, 300 entries | 10.43 ms | 11.68 ms |
| Applications first opening | 187 ms | 184 ms |
| Applications warm opening | 156 ms | 151 ms |
| Idle host process-group RSS | 177.05 MiB | 177.79 MiB |
| Open Applications process-group RSS | 220.90 MiB | 219.50 MiB |
| Released process-group RSS | 190.74 MiB | 187.00 MiB |
| Python workers after explicit release | 0 | 0 |

The Applications query regression triggered another comparison. Original
production sources were restored for three launches, then the reviewed sources
were restored for three launches immediately afterward. Query medians were
12.20 ms original and 12.39 ms reviewed (+1.6%). Original raw results ranged
11.53–12.43 ms; reviewed results ranged 11.58–12.51 ms. In that comparison,
cold opening was 182 → 183 ms, warm opening 152 → 151 ms, open RSS
220.19 → 219.81 MiB and released RSS 186.56 → 188.05 MiB.
The first comparison's timing/memory gains and query regression did not reproduce
consistently. Treat responsiveness and RSS as tied; no broad speed, steady CPU or
power gain is claimed. Short idle CPU/context-switch samples remain near the
measurement floor. Retained modules intentionally keep their owned memory and
processes until explicit Close; the release phase measures Close, rather than
Escape or Desktop.

| Experiment | Hypothesis, evidence and change | Decision |
| --- | --- | --- |
| 1. Explicit lifetime and one keyboard owner | Feature-driven retention made navigation and completion destroy user state. The native test reproduces lost keyboard delivery after Escape in the original sources. Remove retention bookkeeping and use one transient exclusive surface for pills/module input, with a passive desktop bar. Native testing also exposed hidden content shrinking during desktop popups; preserve the host's full-screen geometry. Target: persistent object identity, native key delivery and explicit teardown. Expected tradeoff: opened modules retain resources. | Keep for correctness and simpler ownership. Native Escape/return, drawer/popup dismissal, query preservation, window actions and monitor migration pass. The fixed offscreen workload is effectively tied. |
| 2. Actual activity and idle monitoring | Initial status loading opened an empty activity popup; persistent modules would also retain unconditional Files/torrent timers. Gate the popup on real activity. Poll Files editing sessions only while active; pause hidden idle torrent monitoring and refresh on return. Target: no empty popup, idle timers off, active work still monitored. | Keep. Real activity/worker/module smokes verify dismissal, hidden idle suspension, foreground refresh, retained completed jobs and active background work. Files' unconditional one-second idle timer is removed. No battery or native CPU gain is inferred from this. |
| 3. Lazy Action artwork | A static `AppIcon` reference in every generic control imported Quickshell into portable QML and created blank artwork in default text/Lucide controls. Load it only when brand artwork is supplied. Target: portable compilation and removal of unnecessary default artwork creation. | Keep as a dependency cleanup. All 53 portable QML tests pass; the baseline had five compile failures. The profile records 15 default-Action AppIcon ranges before and none after. Real application icon creation dominates, so this is not a material benchmark speed/memory win. |

One QML profile was captured for each endpoint with JavaScript, binding,
creation, signal and compilation events. The XML includes inconsistent negative
duration ranges; aggregated profile timings were discarded. Creation metadata
still distinguishes default Action artwork from actual application artwork.
Total AppIcon root creation ranges are essentially unchanged (11,409 → 11,391),
consistent with keeping actual icons. Profile timings never enter comparisons.

Final verification passes Ruff lint/format, ty, 610 Python tests, 53 portable QML
tests, 20 JavaScript tests, backend budgets and all 24 smoke scripts through
`make check`, including the required media checks. The isolated native focus
runner fails on original Escape behavior and passes the reviewed behavior;
`--window-controls` passes native window actions and retained screen migration.
Those tests do not establish GPU pacing, physical hotplug, input-method behavior,
provider latency or whole-desktop power/resource usage.

Raw reports are `tests/artifacts/performance-review-before.json`,
`performance-review-lifecycle.json` (three-launch intermediate),
`performance-review-after.json`, `performance-review-before-repeat.json` and
`performance-review-after-repeat.json`. Baseline/final `.qtd` traces, creation
counts, original/final native focus logs, native window-control log and full
verification log share that ignored directory. The three-hypothesis bound is
complete; further optimization needs a representative native performance trace.
