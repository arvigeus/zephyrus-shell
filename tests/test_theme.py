import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from services import theme


class ThemeTests(unittest.TestCase):
    def test_portable_qml_defaults_match_authoritative_json(self):
        text = (theme.ROOT / "core/theme/Defaults.js").read_text()
        self.assertEqual(json.loads(text.split("var settings = ", 1)[1].rstrip(";\n")), json.loads(theme.DEFAULTS.read_text()))

    def test_bundled_icon_markup_is_available_for_light_foregrounds(self):
        result = theme.effective(theme.load(Path("/nonexistent/theme-test")))
        self.assertIn('stroke="#f1f2f6"', result["icons"]["wifi"])
        self.assertIn("<svg", result["icons"]["star-filled"])

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config, self.data, self.state = (self.root / name for name in ("config", "data", "state"))
        self.settings = theme.load(self.config)
        self.sync = theme.Synchronizer(self.config, self.data, self.state)

    def write(self, relative, content):
        path = self.config / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_partial_override_merges_and_invalid_input_is_rejected(self):
        self.write("zephyrus-shell/theme.json", '{"font_size":13,"palettes":{"dark":{"accent":"#123456"}}}')
        result = theme.load(self.config)
        self.assertEqual(result["palettes"]["dark"]["accent"], "#123456")
        self.assertEqual(result["font_size"], 13)
        self.assertEqual(result["palettes"]["dark"]["background"], "#1b2021")
        for overrides in ({"mode": "bad"}, {"font": "bad\nfont"}, {"font_size": True},
                          {"font_size": float("nan")}, {"font_size": 25}, {"sync_desktop": 1},
                          {"palettes": {"dark": {"accent": "red"}}}, {"unknown": 2}):
            self.write("zephyrus-shell/theme.json", json.dumps(overrides))
            with self.assertRaises(ValueError):
                theme.load(self.config)

    def test_dark_light_colors_and_fonts_reach_toolkits(self):
        self.write("zed/settings.json", '{"git":{"inline_blame":{"enabled":false}}}')
        self.write("Code - OSS/User/settings.json", '{"editor.tabSize":4}')
        for mode in ("dark", "light"):
            self.settings.update(mode=mode, font="DejaVu Sans", font_size=13,
                                 monospace_font="DejaVu Sans Mono", monospace_font_size=12)
            self.sync.apply(self.settings)
            c = self.settings["palettes"][mode]
            kde = theme.read(self.config / "kdeglobals")
            self.assertIn("BackgroundNormal=" + theme.rgb(c["background"]), kde)
            self.assertIn("font=DejaVu Sans,13,", kde)
            self.assertIn("fixed=DejaVu Sans Mono,12,", kde)
            gtk = theme.read(self.config / "gtk-3.0/settings.ini")
            self.assertIn("gtk-font-name=DejaVu Sans 13", gtk)
            self.assertIn("gtk-application-prefer-dark-theme=" + str(mode == "dark").lower(), gtk)
            css = theme.read(self.config / "gtk-4.0/gtk.css")
            self.assertIn("--window-bg-color: " + c["background"], css)
            self.assertIn("@define-color theme_selected_bg_color_breeze " + c["accent"], css)
            kitty = theme.read(self.config / "kitty/kitty.conf")
            self.assertIn("background " + c["background"], kitty)
            self.assertIn("font_family DejaVu Sans Mono", kitty)
            zed = json.loads(theme.read(self.config / "zed/settings.json"))
            self.assertEqual(zed["ui_font_size"], 13 * 4 / 3)
            self.assertEqual(zed["theme"]["mode"], mode)
            code = json.loads(theme.read(self.config / "Code - OSS/User/settings.json"))
            self.assertEqual(code["workbench.colorCustomizations"]["editor.background"], c["background"])
            self.assertEqual(code["editor.fontSize"], 16)
            self.assertEqual(code["editor.tabSize"], 4)

    def test_repeated_apply_is_idempotent_and_css_has_one_block(self):
        self.write("gtk-3.0/gtk.css", "@import 'colors.css';\n/* Custom styles */\n")
        self.sync.apply(self.settings)
        self.assertEqual(self.sync.apply(self.settings), [])
        self.settings["palettes"]["dark"]["accent"] = "#224466"
        self.sync.apply(self.settings)
        css = theme.read(self.config / "gtk-3.0/gtk.css")
        self.assertEqual(css.count("Zephyrus theme begin"), 1)
        self.assertEqual(css.count("Zephyrus theme end"), 1)
        self.assertTrue(css.startswith("@import 'colors.css';"))
        self.assertIn("#224466", css)
        self.assertNotIn("#ff465c", css)

    def test_ini_preserves_unrelated_settings_and_comments(self):
        path = self.write("kdeglobals", "# personal\n[General]\nTerminalApplication=kitty\nfont=old\n[Icons]\nTheme=old\n[Other]\nValue=100%\n")
        self.sync.apply(self.settings)
        self.assertIn("# personal", path.read_text())
        self.assertIn("TerminalApplication=kitty", path.read_text())
        self.assertIn("Value=100%", path.read_text())
        self.assertNotIn("font=old", path.read_text())
        self.assertNotIn("Theme=old", path.read_text())

    def test_jsonc_preserves_comments_nested_settings_urls_and_trailing_commas(self):
        text = '''// settings
{
  "url": "https://example.com/a/*b*/",
  "theme_overrides": {"One Dark": {"syntax": {"comment": {"font_style": "italic"}},}},
  "editor.fontFamily": "Old", // font comment
}'''
        result = theme.jsonc_merge(text, {"editor.fontFamily": "New", "new": 42,
            "theme_overrides": {"One Dark": {"background": "#112233"}}})
        self.assertIn("// settings", result)
        self.assertIn("// font comment", result)
        self.assertIn("https://example.com/a/*b*/", result)
        parsed = json.loads(theme.jsonc_clean(result))
        self.assertEqual(parsed["theme_overrides"]["One Dark"]["syntax"]["comment"]["font_style"], "italic")
        self.assertEqual(parsed["theme_overrides"]["One Dark"]["background"], "#112233")
        self.assertEqual(parsed["editor.fontFamily"], "New")
        self.assertEqual(theme.jsonc_merge(result, {"new": 42}), result)

    def test_invalid_editor_settings_prevents_all_desktop_writes(self):
        self.write("zed/settings.json", "{broken")
        with self.assertRaises(ValueError):
            self.sync.apply(self.settings)
        self.assertFalse((self.config / "kdeglobals").exists())
        self.assertFalse(self.sync.manifest.exists())

    def test_restore_original_files_symlinks_and_remove_generated_files(self):
        original = "# personal\n[General]\nTerminalApplication=kitty\n"
        self.write("kdeglobals", original)
        link = self.config / "kitty/kitty.conf"
        link.parent.mkdir(parents=True)
        target = self.root / "dotfile.conf"
        target.write_text("font_size 10\n")
        link.symlink_to(target)
        self.sync.apply(self.settings)
        self.assertFalse(link.is_symlink())
        self.assertEqual(target.read_text(), "font_size 10\n")
        self.sync.restore()
        self.assertEqual((self.config / "kdeglobals").read_text(), original)
        self.assertEqual(link.resolve(), target)
        self.assertFalse((self.data / "color-schemes/Zephyrus.colors").exists())

    def test_edited_generated_file_stops_restore_before_any_deletion(self):
        self.sync.apply(self.settings)
        self.write("kitty/kitty.conf", "user edit")
        with self.assertRaisesRegex(ValueError, "Preserve edits"):
            self.sync.restore()
        self.assertTrue((self.config / "kdeglobals").exists())
        self.assertEqual((self.config / "kitty/kitty.conf").read_text(), "user edit")

    def test_failed_write_rolls_back_files_and_keeps_existing_manifest(self):
        self.sync.apply(self.settings)
        prior = self.sync.manifest.read_bytes()
        files = {path: path.read_bytes() for path in theme.render(self.settings, self.config, self.data)}
        changed = copy.deepcopy(self.settings)
        changed["mode"] = "light"
        original = theme.atomic_write
        def fail(path, content, mode=0o600):
            if path == self.sync.manifest:
                raise OSError("disk full")
            return original(path, content, mode)
        with patch.object(theme, "atomic_write", fail), self.assertRaises(OSError):
            self.sync.apply(changed)
        self.assertEqual(self.sync.manifest.read_bytes(), prior)
        for path, content in files.items():
            self.assertEqual(path.read_bytes(), content)

    def test_failure_midway_through_application_rolls_back_and_can_retry(self):
        original = self.write("kdeglobals", "[General]\nTerminalApplication=kitty\n")
        content = original.read_bytes()
        write = theme.atomic_write
        failed = False
        def fail_once(path, value, mode=0o600):
            nonlocal failed
            if path == self.config / "gtk-4.0/gtk.css" and not failed:
                failed = True
                raise OSError("interrupted write")
            return write(path, value, mode)
        with patch.object(theme, "atomic_write", fail_once), self.assertRaises(OSError):
            self.sync.apply(self.settings)
        self.assertEqual(original.read_bytes(), content)
        self.assertFalse((self.data / "color-schemes/Zephyrus.colors").exists())
        self.assertFalse(self.sync.manifest.exists())
        self.sync.apply(self.settings)
        self.sync.restore()
        self.assertEqual(original.read_bytes(), content)

    def test_notifications_capture_original_settings_and_emit_palette_and_font_changes(self):
        self.sync.apply(self.settings)
        calls = []
        def run(command):
            calls.append(command)
            return "'old'" if command[1] == "get" else ""
        with patch.object(theme, "run", run), patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}):
            self.assertEqual(theme.notify(self.settings, self.sync), [])
        saved = json.loads(self.sync.manifest.read_text())["settings"]
        self.assertEqual(saved["font-name"]["before"], "'old'")
        self.assertEqual(saved["font-name"]["installed"], "'Noto Sans 11'")
        self.assertEqual([call[-2] for call in calls if call[0] == "gdbus"], ["0", "1", "2"])
        self.assertTrue(any("prefer-dark" in call[-1] for call in calls))

    def test_real_cli_respects_xdg_and_no_notify(self):
        env = {**os.environ, **{key: str(path) for key, path in zip(
            ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"), (self.config, self.data, self.state))}}
        cli = ["python3", str(theme.ROOT / "scripts/theme.py")]
        first = json.loads(subprocess.check_output(cli + ["apply", "--no-notify"], env=env))
        self.assertTrue(first["changed"])
        self.assertEqual(first["warnings"], [])
        subprocess.check_call(cli + ["set-mode", "light"], env=env, stdout=subprocess.DEVNULL)
        second = json.loads(subprocess.check_output(cli + ["apply", "--no-notify"], env=env))
        self.assertEqual(second["theme"]["mode"], "light")
        subprocess.check_call(cli + ["restore"], env=env, stdout=subprocess.DEVNULL)
        self.assertFalse((self.config / "kdeglobals").exists())
        self.assertTrue(theme.source(self.config).exists())

    def test_flatpak_theme_access_is_targeted_preserves_denials_and_restores(self):
        app = "org.example.App"
        folder = self.data / "flatpak/overrides"
        folder.mkdir(parents=True)
        path = folder / app
        original = "[Context]\nfilesystems=xdg-download;!xdg-config/gtk-3.0;\n[Environment]\nOTHER=value\n"
        path.write_text(original)
        self.sync.apply(self.settings, [app])
        content = path.read_text()
        self.assertIn("!xdg-config/gtk-3.0;", content)
        self.assertIn("xdg-config/gtk-4.0:ro;", content)
        self.assertIn("xdg-config/kdeglobals:ro;", content)
        self.assertIn("OTHER=value", content)
        self.assertNotIn("filesystems=home", content)
        self.assertEqual(self.sync.apply(self.settings, [app]), [])
        self.sync.restore()
        self.assertEqual(path.read_text(), original)

    def test_vlc_forced_dark_is_disabled_without_changing_other_options(self):
        path = self.write("vlc/vlcrc", "[core]\none-instance=1\n[qt]\nqt-dark-palette=1\nqt-max-volume=200\n")
        self.settings["mode"] = "light"
        self.sync.apply(self.settings)
        self.assertIn("qt-dark-palette=0", path.read_text())
        self.assertIn("qt-max-volume=200", path.read_text())


if __name__ == "__main__":
    unittest.main()
