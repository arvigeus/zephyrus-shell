# Shared desktop appearance

Zephyrus has one theme source: `$XDG_CONFIG_HOME/zephyrus-shell/theme.json`
(normally `~/.config/zephyrus-shell/theme.json`). The real shell creates it on
first application and watches edits. Colors, fonts and font sizes feed the shell
and application adapters together. Invalid edits leave the last valid appearance
in place and report an error. Defaults live in `config/theme.json`.

The source contains `mode` (`dark` or `light`), `font`, `font_size`,
`monospace_font`, `monospace_font_size`, `sync_desktop`, and separate
`palettes.dark` / `palettes.light` objects. Each palette contains `background`,
`surface`, `raised`, `border`, `text`, `muted`, `accent`, `accent_text`, `danger`,
`warning`, `success`, and `link_visited`, using opaque `#RRGGBB` colors. Partial
files merge with defaults; unknown keys and invalid values are rejected.

For example, this override keeps the default palettes and changes the accent and
typography:

```json
{
  "font": "Noto Sans",
  "font_size": 12,
  "monospace_font": "Noto Sans Mono",
  "monospace_font_size": 11,
  "palettes": {
    "dark": {"accent": "#cf527d"}
  }
}
```

Use installed font families. Font sizes are **points**, independent of monitor
scale. GTK, KDE and Kitty receive point sizes; Zed and VS Code receive the
equivalent logical pixels (points × 96/72). Shell labels preserve their current
relative hierarchy and scale from the 11-point baseline with `Theme.sp(size)`.
Compositor output scaling remains a separate display preference. hyprqt6engine
accepts integer font sizes, so its optional adapter rounds fractional sizes.
Shell icons reuse the bundled Lucide SVGs and recolor their foreground, accent
and destructive strokes from the same tokens, including in light mode.

Apply or inspect from the checkout:

```sh
python3 scripts/theme.py get
python3 scripts/theme.py apply
python3 scripts/theme.py set-mode light
python3 scripts/theme.py set-mode dark
```

`set-mode` changes the source; the running shell watches and applies it. If the
shell is stopped, follow it with `apply`. Settings' System card has a light/dark
toggle between Cleaning and Update. It saves the same source and applies the
change to the shell and supported applications.
`qs -p . ipc call shell reloadTheme` explicitly retries application if needed.
Set `sync_desktop` to `false` for shell-only customization. Ordinary previews read
the same theme but never apply desktop settings.

## Application coverage

| Applications | Integration | Limits |
| --- | --- | --- |
| Dolphin, Koko, Okular, Ark, Kate/KWrite, qBittorrent, Fooyin, MKVToolNix and other native Qt apps | Generated KDE palette, UI/fixed fonts, font sizes, native Kvantum style and Breeze icons | Apps can override their palette; some need reopening |
| VLC | Qt palette; existing user configuration switches off the forced-dark option | Video, subtitles and custom skins have their own styling |
| Meld, virt-manager, GIMP, Satty, Kooha and other GTK apps | GTK 3/4 settings and color CSS; GNOME interface font settings | Individual application themes or custom drawing can override parts |
| Foliate, Dev Toolbox, Bottles and other libadwaita apps | Dark/light portal preference, fonts, documented color variables and legacy named colors | CSS recoloring is version-dependent; native widget layouts remain |
| Kitty | Generated colors and monospace font/size in a managed config block | Reopen or use Kitty's Reload configuration command; remote control is not enabled |
| Zed | UI and buffer fonts/sizes; palette overrides of bundled One Dark/One Light | Configured only if its settings file exists; syntax colors remain the editor's |
| VS Code, Code - OSS, VSCodium | Workbench colors and editor/terminal fonts/sizes | Configured only if its settings exists; VS Code has no supported setting for the general UI font family |
| Firefox, Chromium/Chrome, Zen, Thunderbird, Electron applications | System dark/light preference and toolkit dialogs where supported | Choose System/Automatic inside apps; custom browser themes, page content and Electron UI do not inherit the complete desktop palette |
| LibreOffice and other Flatpaks | Portal settings, host fonts and narrowly scoped per-app access to toolkit appearance configuration | Depends on the app's runtime/backend; running instances need reopening after permission changes |
| Telegram, Discord, Steam, Heroic, Kodi, OnlyOffice, web applications and games | System preference where supported | Their skins and UI fonts cannot be recolored uniformly through KDE/GTK settings; no unsupported client modifications are installed |

The goal is a shared palette and typography across supported toolkits. Different
toolkits retain their widget layouts and spacing; application content is not
rewritten. Fully identical styling across every application requires cooperation
from those applications.

Qt uses `QT_QPA_PLATFORMTHEME=kde` in the Hyprland session. The setup packages
include `plasma-integration` and `plasma5-integration`, which provide standalone
Qt 6 and Qt 5 platform themes without starting a Plasma session. `breeze-gtk`,
`breeze-icons`, `kvantum`, `kvantum-qt5` and the selected fonts must also be installed. The optional
hyprqt6engine config points at the same generated color scheme for users who
explicitly select that engine.

Dark mode uses softer charcoal backgrounds and rose-tinted text with the red
brand accent. Light mode uses soft warm-gray backgrounds and plum-tinted text.
Dolphin's Places sidebar shares its file-view background. Menus use the separate
surface color. Native document tabs have a subtle selected background and accent
underline. Kvantum geometry is adapted from Tsu Jan's KvFlat theme; its source
and GPL license are in `assets/qt-theme/`. Applications keep their own artwork.

The GTK Settings portal is explicitly selected in `hyprland/portals.conf`.
GNOME's interface `color-scheme` setting supplies the standard dark/light
preference. Fonts are advertised through its font settings. Arbitrary accents
are applied through palette/CSS adapters; the portal's limited accent-color
preference is not advertised as an exact arbitrary accent match.

On application, installed Flatpaks receive per-app read access to
`xdg-config/gtk-3.0`, `xdg-config/gtk-4.0`, `xdg-config/kdeglobals`, and `xdg-config/Kvantum`. Existing
permissions and explicit denials are preserved. No global Flatpak permission,
whole-home access or whole-config access is added. Host fonts are already
exposed by Flatpak. Toolkit appearance may differ if Breeze is absent from a
sandbox; the generated CSS still supplies basic colors. Qt Flatpaks need the
Kvantum style in their runtime to inherit the complete widget appearance. Flatpaks installed later
are picked up on the next apply or shell restart.

Hyprland border colors apply live and reload from generated `appearance.lua`.
The shell's procedural background also follows the palette. A user-selected
wallpaper remains artwork. Hyprlock retains its current static appearance;
lock-screen adaptation is a separate follow-up.

## Preservation and restoration

GTK/KDE settings are patched by key, preserving unrelated settings and comments.
CSS and Kitty configuration use replaceable managed blocks. Editor settings
preserve JSONC comments, trailing commas and unrelated options. Appearance keys
owned by sync are reapplied when the theme changes; customize the source instead
of editing generated colors. `apply` is idempotent. Atomic writes replace user
symlinks locally without modifying their repository targets.

The original file contents/symlinks and original desktop font/mode settings are
recorded privately in `$XDG_STATE_HOME/zephyrus-shell/theme-sync.json`. Recovery
data is saved before file changes. Restoration refuses to overwrite edited
application files. Desktop settings changed independently afterward are retained.

Stop automatic theme sync (stop the shell or set `sync_desktop` to `false`) before:

```sh
python3 scripts/theme.py restore
```

The editable theme source is retained. Restoration removes generated files and
restores original application files and recorded settings; it does not uninstall
packages. Theme restoration is independent of development-session teardown.
Session environment changes take full effect after the next login. Existing app
processes are never forcibly restarted or closed.

For repository default changes, run `python3 scripts/theme.py defaults` to refresh
the generated portable QML fallback. Production reads the authoritative JSON;
portable Qt tests use the fallback without depending on the Quickshell executable.
The test suite checks that both match.

## Verification

```sh
python3 -m unittest discover -s tests -p test_theme.py
bash scripts/check-theme.sh
bash scripts/check-theme-toolkits.sh
```

The smoke test uses real theme entry points and isolated XDG directories, with
desktop notifications disabled. It exercises repeated atomic edits, font and
palette propagation, light/dark transitions, malformed input and recovery.
The toolkit check requires development headers, native Kvantum styles and KDE integration
plugins. It verifies real Qt 5/6 palettes and fonts and GTK 3/4 CSS parsers in both
modes, rendering an offscreen gallery and checking the actual menu surface color
without modifying desktop settings.

Upstream references: [GTK shared settings](https://docs.gtk.org/gtk3/class.Settings.html),
[libadwaita color variables](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/css-variables.html),
[portal appearance preference](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html),
[Flatpak desktop and font integration](https://docs.flatpak.org/en/latest/desktop-integration.html),
[Zed appearance overrides](https://zed.dev/docs/themes),
[Kitty configuration](https://sw.kovidgoyal.net/kitty/conf/).

Modules resolve their validated entry paths through the shared module host's QML
context. Preserve the resulting Quickshell URL: converting it to a `file:` URL
creates separate QML singleton instances, leaving module colors and state stale.
Dynamically loaded component directories include `qmldir` type indexes because
Quickshell's initial import scan cannot synthesize indexes for late-loaded files.
The theme smoke test covers live, retained, recreated and fresh light-session
modules without opening Terminal.
