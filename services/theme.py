"""Shared theme source, toolkit adapters and reversible desktop synchronization.

Only the production shell enables writes. Previews use the same validated source
without applying desktop settings. All rendering happens before the first write.
"""

import base64
import copy
import fcntl
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

from services.storage import atomic_write as atomic_write

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = ROOT / "config/theme.json"


def locations():
    home = Path.home()
    return tuple(
        Path(os.environ.get(key, home / fallback))
        for key, fallback in (
            ("XDG_CONFIG_HOME", ".config"),
            ("XDG_DATA_HOME", ".local/share"),
            ("XDG_STATE_HOME", ".local/state"),
        )
    )


def source(config):
    return config / "zephyrus-shell/theme.json"


def load(config):
    defaults = json.loads(DEFAULTS.read_text())
    path = source(config)
    overrides = json.loads(path.read_text()) if path.exists() else {}

    def merge(base, other):
        if not isinstance(other, dict):
            raise ValueError("Theme settings must be objects.")
        for key, value in other.items():
            if key not in base:
                raise ValueError("Unknown theme key: " + key)
            if isinstance(base[key], dict):
                merge(base[key], value)
            else:
                base[key] = value

    merge(defaults, overrides)
    if defaults["mode"] not in ("dark", "light"):
        raise ValueError("Theme mode must be dark or light.")
    if type(defaults["sync_desktop"]) is not bool:
        raise ValueError("sync_desktop must be a boolean.")
    for key in ("font", "monospace_font"):
        if not isinstance(defaults[key], str) or not re.fullmatch(
            r"[\w .+()-]{1,100}", defaults[key]
        ):
            raise ValueError(key + " must be a plain font family name.")
    for key in ("font_size", "monospace_font_size"):
        if type(defaults[key]) not in (int, float) or not 6 <= defaults[key] <= 24:
            raise ValueError(key + " must be between 6 and 24 points.")
    for palette in defaults["palettes"].values():
        for key, value in palette.items():
            if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
                raise ValueError(key + " must use #RRGGBB.")
    return defaults


def effective(theme):
    # Keep bundled SVG geometry; the shared QML icon widget substitutes the
    # foreground at render time, including in software-rendered previews.
    icons = {path.stem: path.read_text() for path in (ROOT / "assets/lucide").glob("*.svg")}
    return {**theme, "colors": theme["palettes"][theme["mode"]], "icons": icons}


def read(path):
    return path.read_text() if path.exists() else ""


def ini_merge(text, groups):
    """Patch managed keys, retaining comments and unrelated KDE/GTK settings."""
    remaining = copy.deepcopy(groups)
    lines, section = [], ""

    def finish():
        for key, value in remaining.pop(section, {}).items():
            lines.append(f"{key}={value}\n")

    for line in text.splitlines(keepends=True):
        match = re.fullmatch(r"\s*\[([^\n]+)\]\s*", line)
        if match:
            finish()
            section = match[1]
        key = (
            line.split("=", 1)[0].strip()
            if "=" in line and not line.lstrip().startswith(("#", ";"))
            else None
        )
        if key in remaining.get(section, {}):
            lines.append(f"{key}={remaining[section].pop(key)}\n")
        else:
            lines.append(line if line.endswith("\n") else line + "\n")
    finish()
    for group, values in remaining.items():
        lines.append(f"\n[{group}]\n")
        lines.extend(f"{key}={value}\n" for key, value in values.items())
    return "".join(lines)


def block(text, content, comment):
    start, end = comment + " Zephyrus theme begin", comment + " Zephyrus theme end"
    if comment == "/*":
        start += " */"
        end += " */"
    text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
    return (
        text.rstrip()
        + ("\n\n" if text.strip() else "")
        + start
        + "\n"
        + content.rstrip()
        + "\n"
        + end
        + "\n"
    )


def jsonc_clean(text, trailing=True):
    # Replace comments with whitespace, keeping offsets for surgical updates.
    pattern = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/'
    clean = re.sub(
        pattern,
        lambda m: (
            m[0] if m[0].startswith('"') else "".join("\n" if ch == "\n" else " " for ch in m[0])
        ),
        text,
        flags=re.S,
    )
    if trailing:
        # Only commas outside strings, immediately before an object/array end.
        clean = re.sub(
            r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])', lambda m: " " if m[0] == "," else m[0], clean
        )
    return clean


def jsonc_merge(text, updates):
    """Preserve JSONC comments and app settings outside the managed keys."""
    text = text or "{}\n"
    clean = jsonc_clean(text)
    value = json.loads(clean)
    if not isinstance(value, dict):
        raise ValueError("Application settings must be a JSON object.")
    decoder, pos, spans = json.JSONDecoder(), clean.index("{") + 1, {}
    while True:
        nonspace = re.search(r"\S", clean[pos:])
        assert nonspace is not None
        pos += nonspace.start()
        if clean[pos] == "}":
            break
        key, pos = decoder.raw_decode(clean, pos)
        pos = clean.index(":", pos) + 1
        nonspace = re.search(r"\S", clean[pos:])
        assert nonspace is not None
        pos += nonspace.start()
        begin = pos
        _, pos = decoder.raw_decode(clean, pos)
        spans[key] = (begin, pos)
        nonspace = re.search(r"\S", clean[pos:])
        assert nonspace is not None
        pos += nonspace.start()
        if clean[pos] == ",":
            pos += 1
    changes, additions = [], {}
    for key, item in updates.items():
        if key in spans:
            begin, end = spans[key]
            replacement = (
                jsonc_merge(text[begin:end], item).rstrip()
                if isinstance(item, dict) and isinstance(value[key], dict)
                else json.dumps(item, ensure_ascii=False)
            )
            changes.append((begin, end, replacement))
        else:
            additions[key] = item
    if additions:
        close = clean.rfind("}")
        before = jsonc_clean(text[:close], trailing=False).rstrip()
        prefix = "," if value and not before.endswith(",") else ""
        content = ",\n".join(
            "  " + json.dumps(key) + ": " + json.dumps(item, ensure_ascii=False)
            for key, item in additions.items()
        )
        changes.append((close, close, prefix + "\n" + content + "\n"))
    for begin, end, replacement in sorted(changes, reverse=True):
        text = text[:begin] + replacement + text[end:]
    json.loads(jsonc_clean(text))
    return text


def rgb(color):
    return ",".join(str(int(color[i : i + 2], 16)) for i in (1, 3, 5))


def contrast_ratio(foreground, background):
    """WCAG contrast for opaque sRGB colors."""

    def luminance(color):
        channels = [int(color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
        linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
        return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722), strict=True))

    lighter, darker = sorted((luminance(foreground), luminance(background)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def qt_selection_text(c):
    # Menu items retain solid accent backgrounds.
    for foreground in (c["accent_text"], c["text"], c["background"], "#000000", "#ffffff"):
        if contrast_ratio(foreground, c["accent"]) >= 4.5:
            return foreground


def mix_colors(first, second, amount):
    return "#" + "".join(
        f"{int(int(first[i : i + 2], 16) * (1 - amount) + int(second[i : i + 2], 16) * amount):02x}"
        for i in (1, 3, 5)
    )


def qt_selection_background(c):
    # Dolphin 26.08 uses Text even for selected filenames, and blends secondary
    # text with Base when unfocused. Accommodate both, including newer versions
    # that use HighlightedText, with a quiet fill and an accent-colored frame.
    secondary = mix_colors(c["text"], c["background"], 0.3)
    for opacity in range(16, -1, -1):
        background = mix_colors(c["background"], c["accent"], opacity / 100)
        if min(contrast_ratio(text, background) for text in (c["text"], secondary)) >= 4.5:
            return background
    return c["background"]


def kde_groups(theme):
    c = theme["palettes"][theme["mode"]]
    selection_text = qt_selection_text(c)
    groups = {
        "General": {"Name": "Zephyrus", "ColorScheme": "Zephyrus"},
        "KDE": {"contrast": "4"},
        "ColorEffects:Inactive": {"Enable": "false"},
    }
    for section, background, alternate in (
        ("Window", "background", "surface"),
        ("View", "background", "surface"),
        ("Button", "raised", "surface"),
        ("Tooltip", "surface", "raised"),
        ("Complementary", "background", "surface"),
        ("Header", "surface", "raised"),
        ("Selection", "accent", "accent"),
    ):
        colors = {
            "BackgroundNormal": background,
            "BackgroundAlternate": alternate,
            "ForegroundNormal": "accent_text" if section == "Selection" else "text",
            "ForegroundInactive": "muted",
            "ForegroundActive": "accent",
            "ForegroundLink": "accent",
            "ForegroundVisited": "link_visited",
            "ForegroundNegative": "danger",
            "ForegroundNeutral": "warning",
            "ForegroundPositive": "success",
            "DecorationFocus": "accent",
            "DecorationHover": "accent",
        }
        groups["Colors:" + section] = {key: rgb(c[token]) for key, token in colors.items()}
        if section == "Selection":
            groups["Colors:" + section].update(
                ForegroundNormal=rgb(selection_text), ForegroundInactive=rgb(selection_text)
            )
    groups["ColorEffects:Disabled"] = {
        "Color": rgb(c["surface"]),
        "ColorAmount": "0",
        "ColorEffect": "0",
        "ContrastAmount": "0.65",
        "ContrastEffect": "1",
        "IntensityAmount": "0.1",
        "IntensityEffect": "2",
    }
    return groups


def qt_style(c):
    """Native Kvantum geometry with colors from the shared palette."""
    selection_background = qt_selection_background(c)
    template = ROOT / "assets/qt-theme"
    svg = (template / "KvFlat.svg").read_text()

    def color(match):
        value = match[0].lower()
        if len(value) == 4:
            value = "#" + "".join(channel * 2 for channel in value[1:])
        r, g, b = (int(value[i : i + 2], 16) for i in (1, 3, 5))
        if max(r, g, b) - min(r, g, b) > 12:
            return c["accent"]
        if r >= 200:
            return c["text"]
        if r >= 120:
            return c["muted"]
        if r >= 70:
            return c["border"]
        return c["surface"]

    # KvFlat uses shorthand colors for button fills and some indicators.
    # Only match paint values, leaving SVG fragment references untouched.
    svg = re.sub(r"(?<=:)#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b", color, svg)
    # Keep KvFlat's one-pixel accent outline; recolor only the selected interiors.
    svg = re.sub(
        r'<path\b[^>]*\bid="itemview-(?:pressed|toggled)"[^>]*>',
        lambda match: re.sub(r"fill:#[0-9a-fA-F]{6}", "fill:" + selection_background, match[0]),
        svg,
    )
    svg = svg.replace("opacity:.92", "opacity:1")
    # Flat document tabs: quiet labels, a subtle selected surface and an
    # accent underline, rather than boxed button borders.
    tabs = []
    for state in ("normal", "focused", "pressed", "toggled"):
        selected = state in ("pressed", "toggled")
        fill = c["background"] if state == "normal" else c["surface"]
        tabs.append(
            f'<g id="zephyrus-tab-{state}"><rect width="64" height="28" fill="{fill}"/>'
            + (f'<rect y="26" width="64" height="2" fill="{c["accent"]}"/>' if selected else "")
            + "</g>"
        )
    svg = svg.replace("</svg>", "".join(tabs) + "</svg>")
    settings = (template / "KvFlat.kvconfig").read_text()
    settings = re.sub(r"(text\.[\w.]*color=)[^\n]+", lambda m: m[1] + c["text"], settings)
    colors = {
        "window.color": "background",
        "base.color": "background",
        "alt.base.color": "surface",
        "button.color": "raised",
        "light.color": "border",
        "mid.light.color": "border",
        "dark.color": "background",
        "mid.color": "border",
        "tooltip.base.color": "surface",
        "text.color": "text",
        "window.text.color": "text",
        "button.text.color": "text",
        "disabled.text.color": "muted",
        "tooltip.text.color": "text",
        "link.color": "accent",
        "link.visited.color": "link_visited",
    }
    settings = ini_merge(
        settings,
        {
            "%General": {
                "comment": "Zephyrus shared palette",
                "translucent_windows": "false",
                "popup_blurring": "false",
                "blurring": "false",
                "no_inactiveness": "true",
            },
            "GeneralColors": {
                **{key: c[token] for key, token in colors.items()},
                "highlight.color": selection_background,
                "inactive.highlight.color": selection_background,
                "highlight.text.color": c["text"],
            },
            "Hacks": {"transparent_dolphin_view": "true"},
            "Dock": {"frame": "false", "interior": "false"},
            "Tab": {
                "frame": "false",
                "interior.element": "zephyrus-tab",
                "text.normal.color": c["muted"],
                "text.focus.color": c["text"],
                "text.press.color": c["text"],
                "text.toggle.color": c["text"],
            },
            "MenuItem": {"text.focus.color": qt_selection_text(c)},
            "ItemView": {
                "text.press.color": c["text"],
                "text.toggle.color": c["text"],
            },
        },
    )
    return settings, svg


def gtk_css(theme, version):
    c = theme["palettes"][theme["mode"]]
    colors = {
        "theme_bg_color": "surface",
        "theme_fg_color": "text",
        "theme_base_color": "background",
        "theme_text_color": "text",
        "theme_selected_bg_color": "accent",
        "theme_selected_fg_color": "accent_text",
        "borders": "border",
        "link_color": "accent",
        "link_visited_color": "link_visited",
        "error_color": "danger",
        "warning_color": "warning",
        "success_color": "success",
        "window_bg_color": "background",
        "window_fg_color": "text",
        "view_bg_color": "background",
        "view_fg_color": "text",
        "headerbar_bg_color": "raised",
        "headerbar_fg_color": "text",
        "headerbar_backdrop_color": "surface",
        "sidebar_bg_color": "background",
        "sidebar_fg_color": "text",
        "sidebar_backdrop_color": "background",
        "card_bg_color": "raised",
        "card_fg_color": "text",
        "dialog_bg_color": "surface",
        "dialog_fg_color": "text",
        "popover_bg_color": "surface",
        "popover_fg_color": "text",
        "accent_bg_color": "accent",
        "accent_fg_color": "accent_text",
        "accent_color": "accent",
        "destructive_bg_color": "danger",
        "destructive_fg_color": "accent_text",
        "destructive_color": "danger",
        "success_bg_color": "success",
        "warning_bg_color": "warning",
        "error_bg_color": "danger",
    }
    css = "".join(f"@define-color {key} {c[token]};\n" for key, token in colors.items())
    # Breeze's stylesheet uses its own names. Derive all normal/backdrop/disabled
    # variants from the same tokens, without replacing widget geometry or assets.
    breeze = {
        "theme_bg_color": "surface",
        "theme_fg_color": "text",
        "theme_base_color": "background",
        "theme_text_color": "text",
        "theme_selected_bg_color": "accent",
        "theme_selected_fg_color": "accent_text",
        "theme_unfocused_bg_color": "surface",
        "theme_unfocused_fg_color": "muted",
        "theme_unfocused_base_color": "background",
        "theme_unfocused_text_color": "muted",
        "theme_unfocused_selected_bg_color": "raised",
        "theme_unfocused_selected_bg_color_alt": "raised",
        "theme_unfocused_selected_fg_color": "text",
        "theme_unfocused_view_bg_color": "background",
        "theme_unfocused_view_text_color": "muted",
        "content_view_bg": "background",
        "theme_view_active_decoration_color": "accent",
        "theme_view_hover_decoration_color": "accent",
        "theme_hovering_selected_bg_color": "accent",
        "borders": "border",
        "unfocused_borders": "border",
        "tooltip_background": "raised",
        "tooltip_text": "text",
        "tooltip_border": "border",
        "link_color": "accent",
        "link_visited_color": "link_visited",
    }
    for widget in ("button", "header", "titlebar"):
        for suffix in (
            "",
            "_normal",
            "_backdrop",
            "_light",
            "_insensitive",
            "_backdrop_insensitive",
        ):
            breeze[f"theme_{widget}_background{suffix}"] = (
                "raised" if widget == "button" else "surface"
            )
            breeze[f"theme_{widget}_foreground{suffix}"] = (
                "muted" if "insensitive" in suffix else "text"
            )
        for kind in ("focus", "hover"):
            for suffix in ("", "_backdrop", "_insensitive", "_backdrop_insensitive"):
                breeze[f"theme_{widget}_decoration_{kind}{suffix}"] = "accent"
        for suffix in ("", "_insensitive", "_backdrop", "_backdrop_insensitive"):
            breeze[f"theme_{widget}_foreground_active{suffix}"] = "accent_text"
    for kind, token in (("error", "danger"), ("warning", "warning"), ("success", "success")):
        for suffix in ("", "_backdrop", "_insensitive", "_insensitive_backdrop"):
            breeze[f"{kind}_color{suffix}"] = token
    for name in ("base_color", "bg_color", "unfocused_bg_color", "selected_bg_color"):
        breeze["insensitive_" + name] = "surface"
    for name in (
        "base_fg_color",
        "fg_color",
        "unfocused_fg_color",
        "selected_fg_color",
        "unfocused_selected_fg_color",
    ):
        breeze["insensitive_" + name] = "muted"
    for name in ("insensitive_borders", "unfocused_insensitive_borders"):
        breeze[name] = "border"
    css += "".join(f"@define-color {key}_breeze {c[token]};\n" for key, token in breeze.items())
    if version == 4:
        # libadwaita >=1.6 uses CSS variables; older versions use named colors.
        variables = {
            key.replace("_", "-"): token
            for key, token in colors.items()
            if not key.startswith("theme_")
        }
        css += (
            ":root {\n"
            + "".join(f"  --{key}: {c[token]};\n" for key, token in variables.items())
            + "}\n"
        )
    # Basic GTK widgets also follow the palette when a sandbox lacks Breeze's
    # theme extension. Leave sizes, radii, icons and layout to the toolkit.
    css += """
window, .background { background-color: @window_bg_color; color: @window_fg_color; }
.view, textview, textview text, treeview, iconview, entry, spinbutton, searchentry {
  background-color: @view_bg_color; color: @view_fg_color;
}
headerbar { background-color: @headerbar_bg_color; color: @headerbar_fg_color; background-image: none; }
popover, menu { background-color: @popover_bg_color; color: @popover_fg_color; }
button { background-color: @card_bg_color; color: @card_fg_color; background-image: none; }
button:hover { border-color: @accent_bg_color; }
button.suggested-action, button:checked, row:selected, .view:selected, selection {
  background-color: @accent_bg_color; color: @accent_fg_color;
}
*:disabled { color: @theme_unfocused_fg_color_breeze; }
"""
    return css


def editor_colors(c):
    return {
        "foreground": c["text"],
        "disabledForeground": c["muted"],
        "focusBorder": c["accent"],
        "editor.background": c["background"],
        "editor.foreground": c["text"],
        "editor.selectionBackground": c["accent"] + "55",
        "editorCursor.foreground": c["accent"],
        "editorLineNumber.foreground": c["muted"],
        "editorLineNumber.activeForeground": c["accent"],
        "sideBar.background": c["surface"],
        "sideBar.foreground": c["text"],
        "activityBar.background": c["raised"],
        "activityBar.foreground": c["text"],
        "titleBar.activeBackground": c["surface"],
        "titleBar.activeForeground": c["text"],
        "statusBar.background": c["raised"],
        "statusBar.foreground": c["text"],
        "panel.background": c["surface"],
        "panel.border": c["border"],
        "input.background": c["raised"],
        "input.foreground": c["text"],
        "input.border": c["border"],
        "button.background": c["accent"],
        "button.foreground": c["accent_text"],
        "list.activeSelectionBackground": c["accent"],
        "list.activeSelectionForeground": c["accent_text"],
        "terminal.background": c["background"],
        "terminal.foreground": c["text"],
    }


def render(theme, config, data, flatpak_ids=()):
    c, dark = theme["palettes"][theme["mode"]], theme["mode"] == "dark"
    icons, gtk_theme = ("breeze-dark", "Breeze-Dark") if dark else ("breeze", "Breeze")
    ui, mono = theme["font_size"], theme["monospace_font_size"]
    files = {}
    files[config / "zephyrus-shell/appearance.lua"] = (
        "-- Generated from zephyrus-shell/theme.json\n"
        "hl.config({ general = { col = { "
        f'active_border = "rgba({c["accent"][1:]}cc)", inactive_border = "rgba({c["border"][1:]}ff)"'
        " } } })\n"
    )
    groups = kde_groups(theme)
    files[data / "color-schemes/Zephyrus.colors"] = ini_merge("", groups)
    groups["General"].update(
        {
            "font": f"{theme['font']},{ui},-1,5,50,0,0,0,0,0",
            "fixed": f"{theme['monospace_font']},{mono},-1,5,50,0,0,0,0,0",
            **{
                key: f"{theme['font']},{ui},-1,5,50,0,0,0,0,0"
                for key in ("menuFont", "toolBarFont", "smallestReadableFont")
            },
        }
    )
    groups["Icons"] = {"Theme": icons}
    groups["KDE"]["widgetStyle"] = "kvantum"
    groups["WM"] = {"activeFont": groups["General"]["font"]}
    files[config / "kdeglobals"] = ini_merge(read(config / "kdeglobals"), groups)
    kvconfig, svg = qt_style(c)
    files[config / "Kvantum/kvantum.kvconfig"] = ini_merge(
        read(config / "Kvantum/kvantum.kvconfig"), {"General": {"theme": "Zephyrus"}}
    )
    files[config / "Kvantum/Zephyrus/Zephyrus.kvconfig"] = kvconfig
    files[config / "Kvantum/Zephyrus/Zephyrus.svg"] = svg
    vlc = config / "vlc/vlcrc"
    if vlc.exists():
        # The distro baseline forces dark; zero selects the system palette.
        files[vlc] = ini_merge(read(vlc), {"qt": {"qt-dark-palette": "0"}})
    engine = config / "hypr/hyprqt6engine.conf"
    files[engine] = block(
        read(engine),
        "theme {\n"
        + f"    color_scheme = {data / 'color-schemes/Zephyrus.colors'}\n    icon_theme = {icons}\n    style = kvantum\n"
        + f"    font = {theme['font']}\n    font_size = {round(ui)}\n"
        + f"    font_fixed = {theme['monospace_font']}\n    font_fixed_size = {round(mono)}\n}}",
        "#",
    )
    for version in (3, 4):
        folder = config / f"gtk-{version}.0"
        files[folder / "settings.ini"] = ini_merge(
            read(folder / "settings.ini"),
            {
                "Settings": {
                    "gtk-application-prefer-dark-theme": str(dark).lower(),
                    "gtk-theme-name": gtk_theme,
                    "gtk-icon-theme-name": icons,
                    "gtk-font-name": f"{theme['font']} {ui:g}",
                }
            },
        )
        # Inline a block at the end of user CSS: works inside Flatpak without
        # exposing a separate host path, and wins over preexisting colors.css.
        files[folder / "gtk.css"] = block(read(folder / "gtk.css"), gtk_css(theme, version), "/*")
    kitty = config / "kitty/kitty.conf"
    terminal = {
        "background": c["background"],
        "foreground": c["text"],
        "cursor": c["accent"],
        "cursor_text_color": c["accent_text"],
        "selection_background": c["accent"],
        "selection_foreground": c["accent_text"],
        "active_tab_background": c["accent"],
        "active_tab_foreground": c["accent_text"],
        "inactive_tab_background": c["surface"],
        "inactive_tab_foreground": c["muted"],
        "font_family": theme["monospace_font"],
        "font_size": mono,
    }
    ansi = [
        c["background"],
        c["danger"],
        c["success"],
        c["warning"],
        "#619aef",
        c["link_visited"],
        "#5abfc4",
        c["text"],
    ]
    terminal.update({f"color{i}": color for i, color in enumerate(ansi + ansi)})
    files[kitty] = block(
        read(kitty), "\n".join(f"{key} {value}" for key, value in terminal.items()), "#"
    )
    zed = config / "zed/settings.json"
    if zed.exists():
        style = {
            "background": c["background"],
            "surface.background": c["surface"],
            "elevated_surface.background": c["raised"],
            "border": c["border"],
            "border.focused": c["accent"],
            "text": c["text"],
            "text.muted": c["muted"],
            "text.accent": c["accent"],
            "editor.background": c["background"],
            "editor.foreground": c["text"],
            "editor.gutter.background": c["background"],
            "status_bar.background": c["surface"],
            "title_bar.background": c["surface"],
            "toolbar.background": c["surface"],
            "tab_bar.background": c["raised"],
            "tab.active_background": c["surface"],
            "tab.inactive_background": c["raised"],
            "panel.background": c["surface"],
            "terminal.background": c["background"],
            "terminal.foreground": c["text"],
            "players": [
                {"cursor": c["accent"], "selection": c["accent"] + "44", "background": c["accent"]}
            ],
        }
        # Override a bundled theme, so no theme installation/restart is needed.
        name = "One Dark" if dark else "One Light"
        files[zed] = jsonc_merge(
            read(zed),
            {
                "theme": {"mode": theme["mode"], "dark": "One Dark", "light": "One Light"},
                "theme_overrides": {name: style},
                "ui_font_family": theme["font"],
                "ui_font_size": ui * 4 / 3,
                "buffer_font_family": theme["monospace_font"],
                "buffer_font_size": mono * 4 / 3,
            },
        )
    for folder in ("Code", "Code - OSS", "VSCodium"):
        settings = config / folder / "User/settings.json"
        if settings.exists():
            files[settings] = jsonc_merge(
                read(settings),
                {
                    "workbench.colorTheme": "Default Dark Modern"
                    if dark
                    else "Default Light Modern",
                    "window.autoDetectColorScheme": False,
                    "workbench.colorCustomizations": editor_colors(c),
                    "editor.fontFamily": theme["monospace_font"],
                    "editor.fontSize": mono * 4 / 3,
                    "terminal.integrated.fontFamily": theme["monospace_font"],
                    "terminal.integrated.fontSize": mono * 4 / 3,
                },
            )
    # Per-app permissions keep the theme visible at GTK/KDE's expected paths.
    # Expose only appearance configuration, never all of ~/.config or $HOME.
    for app_id in flatpak_ids:
        if not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+", app_id):
            raise ValueError("Invalid Flatpak application ID")
        path = data / "flatpak/overrides" / app_id
        text = read(path)
        values = []
        section = ""
        for line in text.splitlines():
            if line.startswith("["):
                section = line.strip()
            if section == "[Context]" and line.startswith("filesystems="):
                values = [item for item in line.partition("=")[2].split(";") if item]
        for name in (
            "xdg-config/gtk-3.0",
            "xdg-config/gtk-4.0",
            "xdg-config/kdeglobals",
            "xdg-config/Kvantum",
        ):
            # A prior explicit permission wins; don't weaken read/write grants
            # or silently undo a user's explicit denial.
            if not any(item.lstrip("!").split(":")[0] == name for item in values):
                values.append(name + ":ro")
        files[path] = ini_merge(text, {"Context": {"filesystems": ";".join(values) + ";"}})
    return files


def snapshot(path):
    if path.is_symlink():
        return {"link": os.readlink(path)}
    if path.exists():
        return {
            "bytes": base64.b64encode(path.read_bytes()).decode(),
            "mode": path.stat().st_mode & 0o777,
        }
    return {}


def fingerprint(path):
    if path.is_symlink():
        return "link:" + os.readlink(path)
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def restore_snapshot(path, saved):
    if "link" in saved:
        path.unlink(missing_ok=True)
        path.symlink_to(saved["link"])
    elif "bytes" in saved:
        atomic_write(path, base64.b64decode(saved["bytes"]), saved["mode"])
    else:
        path.unlink(missing_ok=True)


class Synchronizer:
    def __init__(self, config, data, state):
        self.config, self.data, self.state = config, data, state
        self.manifest = state / "zephyrus-shell/theme-sync.json"

    def apply(self, theme, flatpak_ids=()):
        self.manifest.parent.mkdir(parents=True, exist_ok=True)
        with (self.manifest.parent / "theme-sync.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            files = render(theme, self.config, self.data, flatpak_ids)
            previous_manifest = snapshot(self.manifest)
            manifest = json.loads(read(self.manifest) or '{"files":{},"settings":{}}')
            changed, before = [], {}
            for path, content in files.items():
                if path.exists() and not path.is_file():
                    raise ValueError("A non-file blocks theme sync: " + str(path))
                if read(path) != content:
                    changed.append(path)
                    before[path] = snapshot(path)
            for path in changed:
                key = str(path)
                if key not in manifest["files"]:
                    manifest["files"][key] = {"before": before[path]}
                manifest["files"][key]["previous"] = fingerprint(path)
                manifest["files"][key]["installed"] = hashlib.sha256(
                    files[path].encode()
                ).hexdigest()
            # Write recovery information before touching application files. An
            # interrupted apply can restore either the old or the new version.
            atomic_write(self.manifest, json.dumps(manifest, indent=2) + "\n")
            try:
                for path in changed:
                    atomic_write(path, files[path])
            except BaseException:
                for path, saved in before.items():
                    restore_snapshot(path, saved)
                restore_snapshot(self.manifest, previous_manifest)
                raise
            return [str(path) for path in changed]

    def restore(self):
        if not self.manifest.exists():
            return []
        with (self.manifest.parent / "theme-sync.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            manifest = json.loads(self.manifest.read_text())
            for name, entry in manifest["files"].items():
                if fingerprint(Path(name)) not in (
                    entry["installed"],
                    entry.get("previous", entry["installed"]),
                ):
                    raise ValueError("Preserve edits before restoring theme settings: " + name)
            for name, entry in reversed(list(manifest["files"].items())):
                restore_snapshot(Path(name), entry["before"])
            warnings = restore_settings(manifest.get("settings", {}))
            self.manifest.unlink()
            return warnings


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Command failed: " + command[0])
    return result.stdout.strip()


def settings_values(theme):
    return {
        "color-scheme": "prefer-" + theme["mode"],
        "gtk-theme": "Breeze-Dark" if theme["mode"] == "dark" else "Breeze",
        "icon-theme": "breeze-dark" if theme["mode"] == "dark" else "breeze",
        "font-name": f"{theme['font']} {theme['font_size']:g}",
        "document-font-name": f"{theme['font']} {theme['font_size']:g}",
        "monospace-font-name": f"{theme['monospace_font']} {theme['monospace_font_size']:g}",
    }


def notify(theme, sync):
    warnings = []
    # GNOME's settings portal exports these values to GTK, libadwaita, browsers
    # and Flatpaks. Save original GVariants for restoration, including unset keys.
    with (sync.manifest.parent / "theme-sync.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest = json.loads(sync.manifest.read_text())
        for key, value in settings_values(theme).items():
            try:
                old = run(["gsettings", "get", "org.gnome.desktop.interface", key])
                entry = manifest["settings"].setdefault(key, {"before": old})
                entry["installed"] = "'" + value + "'"
                # Record recovery data before changing dconf.
                atomic_write(sync.manifest, json.dumps(manifest, indent=2) + "\n")
                if old != entry["installed"]:
                    run(
                        ["gsettings", "set", "org.gnome.desktop.interface", key, entry["installed"]]
                    )
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                warnings.append(f"Desktop {key}: {error}")
    for kind in (0, 1, 2):  # KDE palette, fonts and native style; no Plasma process.
        try:
            run(
                [
                    "gdbus",
                    "emit",
                    "--session",
                    "--object-path",
                    "/KGlobalSettings",
                    "--signal",
                    "org.kde.KGlobalSettings.notifyChange",
                    str(kind),
                    "0",
                ]
            )
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            warnings.append("Qt notification: " + str(error))
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        c = theme["palettes"][theme["mode"]]
        try:
            run(
                [
                    "hyprctl",
                    "--batch",
                    f"keyword general:col.active_border rgba({c['accent'][1:]}cc); "
                    f"keyword general:col.inactive_border rgba({c['border'][1:]}ff)",
                ]
            )
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            warnings.append("Window borders: " + str(error))
    return warnings


def restore_settings(settings):
    warnings = []
    for key, entry in settings.items():
        try:
            if run(["gsettings", "get", "org.gnome.desktop.interface", key]) == entry["installed"]:
                run(["gsettings", "set", "org.gnome.desktop.interface", key, entry["before"]])
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            warnings.append(str(error))
    return warnings
