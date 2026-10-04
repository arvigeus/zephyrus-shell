# Verification on this machine

Packaging ownership, 2026-10-04: a local makepkg VCS snapshot produced both
native split archives; metadata, payload exclusions, installed setup/provisioning,
plugin discovery and public entry points passed the three packaging tests.
Session/hardware setup checks passed. The full Python suite ran 390 tests with
one existing clipboard expectation failure (`test_list_ignores_invalid_rows_and_preserves_ids_and_previews`);
its test/backend are unchanged. Node's three tests and Hyprland configuration
verification passed. Portable QML ran 50 passes and one existing MusicPagination
capability assertion failure; its QML/backend/test are unchanged. Offscreen real
module loading/release passed both in the checkout and an extracted package,
including the system Qt 6 terminal widget without the checkout's ignored copy.
Builds used `--nodeps --nocheck`; no pacman
transaction, clean-chroot install, service activation, physical session/login,
DDC or hardware/power behavior was exercised by these checks.


Desktop/settings follow-up, 2026-10-03: the full 367-test Python suite passed.
Native Qt 5/6 offscreen galleries verified palette, font, style and exact menu
surface color in dark and light modes; GTK 3/4 CSS parsing passed. Theme smoke
uses the actual System card button and verifies persisted light/dark roundtrips.
Settings, power and real-cliphist lifecycle smoke checks passed. Live checks
confirmed the 75% scrolling default, both lid switch bindings, clipboard recording
services, preserved disabled laptop output after reload, and notifications on the
focused output's Overlay layer. Physical lid/suspend/resume remains a manual check.
`bash scripts/check-notifications.sh` also verifies real D-Bus notifications,
replacement, quiet mode, popup body rendering, history retention and dismissal.

Search header and clipboard popover, 2026-10-02: 17 focused Python tests, seven
Spaces/clock checks, Settings, Wayland, retained lifecycle, preview rendering
and real-cliphist desktop smoke checks
passed. Clipboard now opens through the production bar button and anchored
popover rather than the module host. The smoke check covers deferred creation,
search, delete, copy, clear, repeated toggling, reopening and worker release,
while preserving the underlying Applications instance. The popover was rendered
and visually inspected. Native pointer and keyboard input in an isolated
headless Hyprland compositor verified repeated icon clicks, inside/outside
clicks, Escape, returning to Applications, drawer transitions and the Search
header button. This caught and fixed a stale right-row input region and duplicate
Escape shortcuts. The test compositor and input client were closed.

Bar input and Spaces search, 2026-10-02: 51 portable QML checks, 20 Attention
Python tests, nine tray checks, six Spaces/clock checks, preview rendering and
Hyprland configuration verification passed. An isolated compositor with a
headless output and native virtual input verified both Win keys, immediate
search typing, Escape, Super+Space chord suppression, and preserving Super mouse
dragging. Production RunningApps and TrayButton accepted right-clicks after their
hover tooltips appeared. The search, window tooltip and resulting context menu
were captured and visually inspected. Today's indicator tests cover due tasks,
completed/future tasks, multi-day events, notifications and date rollover. No
calendar writes ran; temporary windows and the compositor were closed.

Packaging and focus follow-up, 2026-10-02: all 342 Python tests, 51 portable
QML checks and three JavaScript checks passed, together with Media, Modules,
retained lifecycle, Settings, Applications and real-cliphist desktop smoke checks.
An isolated Hyprland compositor using the production appearance and bindings
confirmed that hovering an inactive window-list button for 1.4 seconds leaves
keyboard focus unchanged. Wheel input scrolled an inactive native window by
320 pixels while the other window retained keyboard focus; clicking then focused
the hovered window. Both Win keys, search typing, tooltip right-clicks and Super
mouse dragging passed again. A native capture confirmed light task, calendar and
bell artwork.

Popup dismissal follow-up, 2026-10-01: Attention now uses a native popup anchored
to its clock pill's bar, with a Hyprland focus grab activated after the popup's
surface exists. Native virtual pointer and keyboard input in an isolated headless
compositor verified repeated pill clicks without mouse movement, outside clicks
on every side, inside clicks remaining open, Escape from both the bar and popup,
and reopening/restoring Applications and Music without losing bar input. The
module and bar retain their focus mode while Attention is open.

Dropdown triggers now toggle their current popup and exclude the trigger from
press-outside dismissal. This covers shared choices, media split buttons, Pictures
tags, Settings sleep/shutdown options, Games store options, Music genres, Radio
countries/genres/quality, Projects menus and Files actions. Seven portable popup
checks exercise press/release separately, repeated toggling, outside/Escape
closure and option selection. The full portable QML suite and the Modules,
Settings and Pictures smoke checks passed. Temporary compositor and input clients
were closed; no session power actions ran.

Panel spacing and fullscreen behavior, 2026-09-30: bottom padding is now 2 px,
with the existing 6 px top padding and 34 px controls, reserving 42 px. The desktop
bar uses the Top layer; visible shell modules raise it to Overlay, while drawers
continue to stack above it. An isolated compositor verified maximized windows keep
the panel, fullscreen covers it, and leaving fullscreen restores it. Real mpv
playback of a generated test pattern covered the panel and restored it on exit.
Movies, TV Series and Applications kept their pills visible; Spaces, Attention,
Settings clicks and Escape passed for each. All 44 portable QML checks, the
12 preview captures and retained-module checks passed. The running session has
42 px Top-layer bars on both monitors. Temporary test processes were closed.
VLC and Firefox were not individually exercised.

Compact panel and separate pills, 2026-09-30: the bar now reserves 46 px, with
34 px controls and 6 px outer vertical padding. An isolated compositor rendered
separate Spaces, window-list, clock, tray and Settings pills with two real Kitty
windows and a private StatusNotifierItem; tray activation and all three panel
buttons passed. Applications, Movies and Music still accepted panel clicks and
Escape, including after returning from Attention. Seven drag gesture checks,
preview captures and retained-module checks passed. Temporary test processes
were closed.

Module top-bar input fix, 2026-09-30: reproduced Spaces clicks being routed to
the exclusive-focus module surface in an isolated Hyprland compositor. The bar
now joins the exclusive surfaces while a module is active, and module input
starts below the 66 px bar while its background still fills the screen. Production
surfaces accepted Spaces, Attention and Settings clicks from Applications,
Movies and Music. Escape closed each module and also worked after returning from
Attention with the pointer over the bar. An Applications capture confirmed search
typing. Retained-module lifecycle checks passed; temporary test processes were
closed.

Window-list ordering refresh fix, 2026-09-30: production drop tests exposed
intermediate orders built from mixed old/new positions while Quickshell updated
each client in an IPC response. `WindowOrderModel` now publishes after the batch
finishes and suppresses unchanged orders. All 44 portable QML checks, the
window-order Node suite and preview smoke passed. An isolated compositor exercised
all 12 before/after targets among three windows through production RunningApps,
in both maximized and ordinary half-width columns. Desktop coordinates, published
model and button positions agreed after every drop; logs no longer showed partial
orders. Temporary windows and compositor were closed. A persistent mismatch was
not reproduced, and physical dragging remains for user testing.

Window-list drop-position fix, 2026-09-30: reproduced a committed release
reporting `(0, 0)` after Qt reset the drag centroid, which cleared RunningApps'
drop target. The handler now forwards the released event point's scene position.
All 39 portable QML tests, the window-order Node suite and preview smoke passed.
Regression cases check the final position for a normal drop, a changed insertion
target on release and a release outside the list. Physical dragging remains for
user testing.

Window-list drag follow-up, 2026-09-30: 37 portable QML tests and all three Node
suites passed. Gesture tests use the actual `ReorderDrag` inside a Flickable and
cover ordinary clicks, committed release without accidental activation, and
cancelled grabs. In an isolated Hyprland compositor, real Kitty columns moved
left and right through production `WindowList.reorder` and `RunningApps` drop
entry points; insertion targets, edge scrolling and outside cancellation passed.
Floating-window drops were rejected and reordering preserved pointer position.
The test bar forced its pending Row layout because the locked outer session was
not rendering nested frames. Preview and production Wayland smoke passed; live
config errors are empty and the shell reloaded. Physical dragging remains for
user testing.

Window-list order follow-up, 2026-09-30: the production model reproduced opening
1 and 2, focusing 1, then opening 3 as 1,3,2. Moving the third column to the right
updated it to 1,2,3 in the same running model. Temporary Kitty test windows were
closed and the user's original focus restored. Focused Node tests cover insertion,
column movement, scroll offsets, maximized columns, workspace/monitor separation,
floating windows, missing metadata and QML IPC coordinate sequences. Preview and
production Wayland smoke passed; the actual running-app icon still reached Ready.


Live Hyprland feedback, 2026-09-30: switched the running session to native
scrolling columns and disabled/unloaded hyprbars; removed its repository setup
and startup hooks. All 302 Python tests, 32 portable QML tests, both Node suites,
preview and production Wayland smoke passed. Both repository configuration and
the installed shim passed `Hyprland --verify-config`; live config errors are
empty. Three real Kitty test windows joined scrolling columns, native maximized
state stayed below the 66 px pill reservation, and layout focus could leave a
maximized column. Only test windows were closed, with focus restored afterward.
Alt+F4 is registered; physical key/border gestures remain for user testing.
The production RunningApps component resolved the current ChatGPT desktop entry
and its absolute icon path, and its Image reached Ready. Invalid icon paths in
other installed desktop entries remain blank. The laptop now uses a personal
125% monitor override; window rounding is 8 px and transitions are shorter.


Initial desktop-session preparation, 2026-09-30 (before live feedback): all 302 Python tests, 32 portable QML
tests, both Node suites, all nine smoke scripts (including power and current
Wayland), and offline performance budgets passed. Both repository Lua and the
installed development shim passed `Hyprland --verify-config`. hyprbars built and
loaded through hyprpm at the official 0.56.2 pin; actual plugin options and config
reload were checked in an isolated nested compositor. Production floating rules,
maximized state/restore and opt-in tiling were exercised on real Kitty windows.

The real Nextcloud account and DAV/Music credentials were migrated with private
permissions, and a live read-only calendar refresh returned ready, fresh data.
No events or tasks were written during verification. Focused tests cover
configuration, credential-provider replacement, separate capabilities, DAV scope
and redirects, migration conflicts and interruption recovery. Session tests cover
owned startup/disconnect cleanup and reversible shim setup, backup preservation,
rollback and refusing to remove user edits.

hypridle parsed all three listeners and acquired its lock-notify sleep inhibitor.
hyprlock parsed its configuration and reached session lock in the nested test.
Nested DRM/capture warnings prevented a usable compositor screenshot; no visual
comparison of the actual hyprbars strip is claimed. Lock authentication, real
login startup/teardown, suspend/resume, portal dialogs/sharing and physical
multi-monitor/hotplug still require the [live session checklist](session.md).
The existing KDE session was left running; the nested compositor and test
processes were closed. System packages and reversible user configuration were
installed as part of this session request.

Battery information follow-up, 2026-09-30: machine/settings Python tests cover
Wh and mAh drivers, missing readings, multiple packs, and estimates honoring the
charge limit. `bash scripts/check-power.sh` uses the production PowerSection and
battery-details command with isolated XDG state to verify lazy creation, refresh
without replacing the card, destruction on collapse, and reopening. The actual
battery card was captured and visually inspected. Charge-limit writes and profile
transitions were not exercised.

Architecture review, 2026-09-30: 262 Python tests and 27 portable QML tests passed,
as did both Node suites, Hyprland configuration parsing, all eight README smoke
scripts, and the offline performance budgets. The retained check now includes six
state-transition cases against the production ShellState singleton. The preview
produced twelve captures; Applications and Attention captures were inspected.
The current Wayland desktop harness passed, but live Hyprland input, physical
multi-monitor/hotplug, player playback, and hardware/GPU/power behavior were not
validated in this review. See [architecture review](architecture-review.md).

Weather/hardware follow-up, 2026-09-30: the CPU/GPU source was read directly from
this machine's hwmon sensors; the card selector now prefers package/edge readings.
The full Python suite (275 tests), portable QML suite (32 tests), both Node suites,
preview, retained lifecycle, current Wayland panel smoke and performance budgets
passed. The weather layout was captured and inspected using the production panel
and configured Open-Meteo data. This verifies reads and rendering, not sensor
calibration, thermal behavior under controlled load or live Hyprland input.

## Earlier baseline

Environment: Arch Linux, Quickshell 0.3.1, Qt 6.11.2, Hyprland 0.56.2,
ROG Zephyrus G14 GA402RK. Existing desktop session: KDE Wayland.

- Twelve Python tests pass: audio rule isolation, guarded profile changes,
  pairing confirmation/PIN validation, metadata-only discovery, ordering and disabling,
  invalid-plugin isolation, removal, action allowlist/argument handling,
  and refusing Hyprland logout outside a Hyprland session.
- `Hyprland --verify-config` reports `config ok` for the standalone Lua configuration.
- Three JavaScript assertions test audio route naming, monitor replacement and unplugging.
- Component preview renders seven states to `tests/artifacts/preview-0.png`
  through `preview-6.png`: closed, library, applications, controls, attention,
  inline Wi-Fi and inline Bluetooth.
- The actual Wayland integration harness opens library, Apps, controls, and attention,
  receives a notification over a private D-Bus session, dismisses it, and checks
  state cleanup before exiting.
- Visual inspection verified live battery, network, audio and brightness information.

The private test bus can emit desktop-portal activation warnings; offscreen Qt emits
a window-mask warning. Neither indicates a production shell QML loading failure.

Not exercised: real power/session actions, changing network or audio settings,
actual Bluetooth pairing (agent responses are unit tested), a real application launch, physical multi-monitor hotplug,
or mouse/keyboard behavior inside a live Hyprland session. Those actions are not
claimed as tested merely because the controls rendered. No existing desktop
configuration was replaced and no system packages were installed.

Application lifecycle and favorites: `bash scripts/check-apps.sh` uses an isolated
configuration directory and two shell processes to verify the load gate, default
Favorites view, add/remove behavior, persistence across restart, and destruction.


Settings/display/session follow-up, 2026-10-01: 322 Python tests passed. Power,
Pictures, Settings lifecycle and component preview smoke checks passed. Settings
kept its real drawer instance and fresh hardware snapshot across close/reopen;
closing cancelled a held action, and a completed hold executed exactly once
through an intercepted backend. Display-page and shared-weather captures were
visually inspected. Hyprland configuration verification passed.

An isolated nested Hyprland compositor exercised production display actions:
left-to-right arrangement, scaling, disabling/re-enabling an output and Lua DPMS
`disable`/`enable` passed with no compositor config errors. On the physical
machine, loading the installed `i2c-dev` module exposed the Dell S2722DC on
DisplayPort AUX bus 19. Its read-only VCP brightness query and the production
snapshot both reported brightness as available. The existing selected wallpaper
was synchronized to the lock-background link. Physical idle, suspend/resume,
PAM unlock and prolonged dock sleep still need a fresh-session live check;
tests did not suspend, shut down or log out the user's desktop.

The weather pill passed shared-forecast and visual checks. With explicit user
consent, the real one-shot weather service returned the configured Ha Long
forecast with no error. All monitor pills share that result and the existing
15-minute provider cache.

Capture integration, 2026-10-02: all 12 desktop helper tests passed, including
annotation handoff with paths containing spaces, missing tools, capture
cancellation (including a zero exit without an image), active-window selection
and Kooha process ownership after overlay dismissal. The Settings lifecycle
smoke test and all 12 component preview captures passed. Visual inspection at
1280×800 verified both capture actions fit above the hardware details.
`Hyprland --verify-config` accepted the updated shortcuts.
Satty options/configuration were checked against upstream v0.22.0. The capture
applications were not installed on the host; real screenshot annotation and
portal recording/audio still need a live session check.

`python3 -m unittest discover -s tests -p test_idle.py` checks session isolation,
profile generation, lid locking and rollback after failed service changes.
`bash scripts/check-session-lock.sh` exercises the real Settings toggle, runtime
state and service launcher with isolated XDG paths and fixture service commands.
It captures `tests/artifacts/session-lock.png`; no live power action is executed.
