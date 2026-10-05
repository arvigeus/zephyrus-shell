import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("makepkg"), "Arch makepkg is unavailable")
class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srcinfo = subprocess.check_output(["makepkg", "--printsrcinfo"], cwd=ROOT, text=True)

    def test_arch_metadata_declares_core_and_optional_runtime_dependencies(self):
        self.assertIn("pkgbase = zephyrus-shell-git", self.srcinfo)
        self.assertIn("pkgname = zephyrus-shell-git", self.srcinfo)
        self.assertIn("pkgname = zephyrus-shell-session-git", self.srcinfo)
        self.assertIn("provides = zephyrus-shell", self.srcinfo)
        self.assertIn("conflicts = zephyrus-shell", self.srcinfo)
        for dependency in (
            "quickshell>=0.3.1",
            "qt6-declarative",
            "python",
            "python-dateutil",
            "libpulse",
            "systemd",
            "xdg-utils",
            "xdg-user-dirs",
        ):
            self.assertIn(f"depends = {dependency}", self.srcinfo)
        for dependency in (
            "zephyrus-shell-session-git",
            "hyprqt6engine",
            "networkmanager",
            "bluez",
            "switcheroo-control",
            "mpv",
            "ffmpeg",
        ):
            self.assertTrue(
                any(
                    line.strip().startswith(f"optdepends = {dependency}:")
                    for line in self.srcinfo.splitlines()
                ),
                f"missing optional dependency metadata for {dependency}",
            )
        for dependency in (
            "qmltermwidget>=2.0",
            "hyprland>=0.56.2",
            "ddcutil",
            "cliphist",
            "python-dbus",
        ):
            self.assertIn(f"depends = {dependency}", self.srcinfo)
        self.assertIn("makedepends = git", self.srcinfo)
        self.assertIn(
            "source = zephyrus-shell::git+https://github.com/arvigeus/zephyrus-shell.git",
            self.srcinfo,
        )

    def test_makepkg_builds_local_vcs_snapshot_and_installed_setup_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            packages = work / "packages"
            env = dict(os.environ, PKGDEST=str(packages))
            subprocess.run(
                [str(ROOT / "scripts/build-package.sh"), "--nodeps", "--nocheck", "--nosign"],
                cwd=work,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            archives = list(packages.glob("*.pkg.tar.*"))
            self.assertEqual(len(archives), 2)
            archive = next(path for path in archives if path.name.startswith("zephyrus-shell-git-"))
            metadata = subprocess.check_output(
                ["bsdtar", "-xOf", str(archive), ".PKGINFO"], text=True
            )
            self.assertIn("pkgname = zephyrus-shell-git", metadata)
            self.assertIn("depend = libpulse", metadata)
            payload = work / "payload"
            payload.mkdir()
            subprocess.run(["bsdtar", "-xf", str(archive), "-C", str(payload)], check=True)
            runtime = payload / "usr/share/zephyrus-shell"
            self.assertRegex((runtime / "REVISION").read_text().strip(), r"^[a-f0-9]{40}$")
            self.assertFalse((runtime / "credentials").exists())
            self.assertFalse((runtime / "tests").exists())
            config = work / "home/.config"
            state = work / "home/.local/state"
            env.update(XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state))
            command = ["python3", str(runtime / "scripts/setup-session.py")]
            subprocess.run(
                [*command, "provision", "--home-strategies", str(work / "policies")],
                env=env,
                check=True,
                capture_output=True,
            )
            subprocess.run([*command, "check"], env=env, check=True, capture_output=True)
            self.assertIn(str(runtime), (config / "hypr/hyprland.lua").read_text())
            self.assertFalse(state.exists())
            registry = (runtime / "core/Modules.qml").read_text()
            self.assertIn('"terminal"', registry)
            self.assertIn('"apps"', registry)
            self.assertTrue((runtime / "shell/ModuleOverlay.qml").is_file())

    def test_package_function_stages_payload_and_system_entry_points(self):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "stage"
            sources = Path(directory) / "sources"
            sources.mkdir()
            (sources / "zephyrus-shell").symlink_to(ROOT, target_is_directory=True)
            subprocess.run(
                [
                    "bash",
                    "-c",
                    "set -e; source ./PKGBUILD; srcdir=$2; pkgdir=$1; package_zephyrus-shell-git",
                    "bash",
                    str(stage),
                    str(sources),
                ],
                cwd=ROOT,
                check=True,
            )
            expected = (
                "usr/share/zephyrus-shell/shell.qml",
                "usr/share/zephyrus-shell/scripts/setup-session.py",
                "usr/share/zephyrus-shell/desktop/defaults/settings.ini",
                "usr/share/zephyrus-shell/widgets/Icon.qml",
                "usr/share/zephyrus-shell/core/Paths.qml",
                "usr/share/zephyrus-shell/settings/WarpNetworkRow.qml",
                "usr/share/zephyrus-shell/core/Warp.qml",
                "usr/bin/zephyrus-shell-warp",
                "usr/lib/systemd/system/zephyrus-warp.service",
                "usr/share/zephyrus-shell/systemd/system/warp-on-demand.conf",
                "usr/share/zephyrus-shell/scripts/warp.py",
                "usr/share/zephyrus-shell/assets/brands/cloudflare.svg",
                "usr/bin/zephyrus-shell",
                "usr/bin/zephyrus-shell-session",
                "usr/bin/zephyrus-shell-hardware",
                "usr/share/color-schemes/Zephyrus.colors",
                "usr/share/wayland-sessions/zephyrus.desktop",
                "usr/lib/systemd/user/zephyrus-clipboard@.service",
                "usr/lib/zephyrus-shell/cpu-boost",
                "usr/share/polkit-1/actions/org.zephyrus-shell.cpu-boost.policy",
            )
            for relative in expected:
                with self.subTest(path=relative):
                    self.assertTrue((stage / relative).is_file())
            self.assertTrue(os.access(stage / "usr/bin/zephyrus-shell", os.X_OK))
            self.assertFalse((stage / "usr/share/zephyrus-shell/.git").exists())
            self.assertFalse((stage / "usr/share/zephyrus-shell/tests").exists())
            self.assertFalse((stage / "usr/share/zephyrus-shell/system").exists())
            self.assertFalse((stage / "usr/share/zephyrus-shell/scripts/setup-system.sh").exists())
            self.assertFalse(
                (
                    stage
                    / "usr/share/zephyrus-shell/plugins/terminal/QMLTermWidget/libqmltermwidget.so"
                ).exists()
            )


if __name__ == "__main__":
    unittest.main()
