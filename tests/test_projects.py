import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from modules.projects import backend


class ProjectsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.projects = self.home / "Work"
        self.projects.mkdir()
        environment = patch.dict(
            os.environ,
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / "config"),
                "XDG_DATA_HOME": str(self.home / "data"),
                "XDG_CACHE_HOME": str(self.home / "cache"),
                "XDG_PROJECTS_DIR": str(self.projects),
            },
        )
        environment.start()
        self.addCleanup(environment.stop)

    def test_lists_unregistered_folders_by_open_time_and_detects_metadata(self):
        alpha = self.projects / "alpha"
        alpha.mkdir()
        (alpha / "package.json").write_text('{"dependencies":{"react":"1","vite":"1"}}')
        (alpha / "public").mkdir()
        (alpha / "public/favicon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        beta = self.projects / "beta"
        beta.mkdir()
        (beta / "Cargo.toml").write_text('[package]\nname="beta"')
        (self.projects / ".hidden").mkdir()
        (self.projects / "alias").symlink_to(alpha, target_is_directory=True)
        backend.write_history({str(beta): 200, str(alpha): 100})

        result = backend.list_projects()

        self.assertEqual([project["name"] for project in result["projects"]], ["beta", "alpha"])
        self.assertEqual(result["projects"][1]["logo"], (alpha / "public/favicon.svg").as_uri())
        self.assertIn("react", [badge["icon"] for badge in result["projects"][1]["badges"]])
        self.assertEqual(result["projects"][0]["symbol"], "rust")

    def test_technologies_are_saved_and_refreshed_explicitly(self):
        project = self.projects / "web"
        project.mkdir()
        manifest = project / "package.json"
        manifest.write_text('{"dependencies":{"react":"1"}}')

        first = backend.list_projects()["projects"][0]["badges"]
        self.assertIn("react", [badge["icon"] for badge in first])
        self.assertTrue(backend.profiles_path().is_file())
        self.assertIn(str(project), backend.read_profiles())

        manifest.write_text('{"dependencies":{"vue":"1"}}')
        with patch.object(backend, "technologies", side_effect=AssertionError("rescanned")):
            self.assertEqual(backend.list_projects()["projects"][0]["badges"], first)

        backend.refresh_profile(str(project))
        refreshed = backend.list_projects()["projects"][0]["badges"]
        self.assertIn("vuejs", [badge["icon"] for badge in refreshed])
        self.assertNotIn("react", [badge["icon"] for badge in refreshed])
        manifest.write_text('{"dependencies":{"svelte":"1"}}')
        all_refreshed = backend.run({"op": "refreshAllProfiles"})["projects"][0]["badges"]
        self.assertIn("svelte", [badge["icon"] for badge in all_refreshed])

    def test_new_folder_is_detected_without_opening_and_failed_save_is_reported(self):
        backend.list_projects()
        project = self.projects / "new"
        project.mkdir()
        (project / "go.mod").write_text("module example.org/new\n")
        with patch.object(backend, "write_profiles", side_effect=OSError("read only")):
            result = backend.list_projects()
        self.assertEqual(result["projects"][0]["name"], "new")
        self.assertEqual(result["projects"][0]["symbol"], "go")
        self.assertIn("could not be saved", result["warning"])
        backend.list_projects()
        self.assertIn(str(project), backend.read_profiles())

    def test_invalid_saved_profile_is_rebuilt(self):
        project = self.projects / "rust"
        project.mkdir()
        (project / "Cargo.toml").write_text("[package]\nname='rust'\n")
        cache = backend.profiles_path()
        cache.parent.mkdir(parents=True)
        cache.write_text(
            '{"version":1,"projects":{"'
            + str(project)
            + '":{"device":0,"inode":0,"badges":[{"icon":"../../other","label":"Bad"}]}}}'
        )
        result = backend.list_projects()
        self.assertEqual(result["projects"][0]["symbol"], "rust")
        self.assertEqual(backend.read_profiles()[str(project)]["badges"][0]["icon"], "rust")

    def test_scaffolder_result_replaces_initial_empty_profile(self):
        project = self.projects / "fresh"
        project.mkdir()
        self.assertEqual(backend.list_projects()["projects"][0]["badges"], [])
        (project / "Cargo.toml").write_text("[package]\nname='fresh'\n")
        self.assertEqual(backend.list_projects()["projects"][0]["badges"], [])
        backend.refresh_profile(str(project))
        self.assertEqual(backend.list_projects()["projects"][0]["symbol"], "rust")

    def test_optional_syntaxis_history_orders_scanned_folders_only(self):
        alpha = self.projects / "alpha"
        beta = self.projects / "beta"
        alpha.mkdir()
        beta.mkdir()
        registry = self.home / "data/syntaxis/workspaces.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(
            '{"workspaces":['
            '{"root":"' + str(beta) + '","last_opened_unix_ms":500},'
            '{"root":"' + str(self.home / "outside") + '","last_opened_unix_ms":900}'
            "]}"
        )
        self.assertEqual(
            [entry["name"] for entry in backend.list_projects()["projects"]], ["beta", "alpha"]
        )

    def test_open_uses_zed_and_persists_order(self):
        project = self.projects / "mine"
        project.mkdir()
        with (
            patch.object(backend.shutil, "which", return_value="/usr/bin/zed"),
            patch.object(backend.subprocess, "Popen") as launch,
        ):
            backend.open_project(str(project))
        self.assertEqual(launch.call_args.args[0], ["/usr/bin/zed", str(project)])
        self.assertGreater(backend.list_projects()["projects"][0]["opened"], 0)
        with self.assertRaises(ValueError):
            backend.open_project(str(self.home))

    def test_create_empty_and_reject_existing_or_escaping_destinations(self):
        result = backend.create_project("hello", "empty")
        self.assertEqual(result["path"], str(self.projects / "hello"))
        self.assertTrue((self.projects / "hello").is_dir())
        with self.assertRaises(ValueError):
            backend.create_project("hello", "empty")
        with self.assertRaises(ValueError):
            backend.create_project("../escape", "empty")
        self.assertFalse((self.home / "escape").exists())

    def test_starter_creates_project_and_interactive_mise_script(self):
        with patch.object(backend.shutil, "which", return_value="/usr/bin/mise"):
            result = backend.create_project("sample", "rust")
        script = Path(result["setupScript"])
        self.assertIn("mise x rust@stable -- cargo init", script.read_text())
        self.assertIn("mise use -y rust@stable", script.read_text())
        self.assertEqual(result["path"], str(self.projects / "sample"))
        self.assertTrue((self.projects / "sample").is_dir())
        self.assertEqual(backend.setup_status(result["setupId"]), {"done": False})
        (backend.setup_root() / (result["setupId"] + ".status")).write_text("0\n")
        self.assertTrue(backend.setup_status(result["setupId"])["success"])
        self.assertFalse(script.exists())

    def test_vite_plus_uses_existing_vp_without_mise(self):
        with patch.object(
            backend.shutil,
            "which",
            side_effect=lambda name: "/usr/bin/vp" if name == "vp" else None,
        ):
            result = backend.create_project("web", "vite-plus")
        self.assertIn("vp create --directory .", Path(result["setupScript"]).read_text())
        self.assertTrue((self.projects / "web").is_dir())

    def test_interactive_setup_records_real_command_result(self):
        project = self.projects / "sample"
        project.mkdir()
        shell = self.home / "finish-shell"
        shell.write_text("#!/bin/sh\nexit 0\n")
        shell.chmod(0o700)
        for command, success in (("true", True), ("false", False)):
            result = backend.prepare_setup(project, command)
            environment = dict(os.environ, SHELL=str(shell))
            backend.subprocess.run(
                ["bash", result["setupScript"]], env=environment, capture_output=True, check=True
            )
            self.assertEqual(backend.setup_status(result["setupId"])["success"], success)
            self.assertFalse(Path(result["setupScript"]).exists())
        abandoned = backend.prepare_setup(project, "true")
        self.assertTrue(backend.discard_setup(abandoned["setupId"])["discarded"])
        self.assertFalse(Path(abandoned["setupScript"]).exists())

    def test_clone_uses_argument_array_and_validates_url(self):
        with (
            patch.object(backend.shutil, "which", return_value="/usr/bin/git"),
            patch.object(backend, "run_managed") as command,
        ):

            def complete_clone(arguments, **_kwargs):
                Path(arguments[-1]).mkdir()
                return backend.subprocess.CompletedProcess(arguments, 0, "", "")

            command.side_effect = complete_clone
            backend.clone_project("https://example.org/team/repo.git", "repo")
        actual = command.call_args.args[0]
        self.assertEqual(
            actual[:5],
            ["/usr/bin/git", "clone", "--progress", "--", "https://example.org/team/repo.git"],
        )
        self.assertEqual(Path(actual[5]).name, "repo")
        self.assertEqual(Path(actual[5]).parent.parent, self.projects)
        self.assertTrue((self.projects / "repo").is_dir())
        with self.assertRaises(ValueError):
            backend.clone_project("file:///tmp/private", "other")
        with patch.object(backend.shutil, "which", return_value="/usr/bin/git"):
            self.assertIn(
                "--filter=blob:none",
                backend.clone_arguments("https://example.org/repo", "blob", "blobless")[2],
            )
            self.assertIn(
                "--depth=1",
                backend.clone_arguments("https://example.org/repo", "shallow", "shallow")[2],
            )

    def test_async_clone_finishes_and_cancellation_cleans_staging(self):
        script = (
            "import pathlib, sys, time; "
            "pathlib.Path(sys.argv[2]).mkdir(); "
            "print('Receiving objects: 100%', file=sys.stderr, flush=True); "
            "time.sleep(float(sys.argv[1]))"
        )

        def wait_for(job_id):
            for _ in range(100):
                result = backend.clone_status(job_id)
                if result["done"]:
                    return result
                time.sleep(0.03)
            self.fail("Clone job did not finish")

        def arguments(_url, name, _mode):
            return "example", self.projects / name, [sys.executable, "-c", script, "0.1"]

        with patch.object(backend, "clone_arguments", side_effect=arguments):
            finished = wait_for(backend.clone_start("example", "complete", "full")["id"])
        self.assertFalse(finished["error"])
        self.assertEqual(finished["percent"], 100)
        self.assertTrue((self.projects / "complete").is_dir())

        def slow_arguments(_url, name, _mode):
            return "example", self.projects / name, [sys.executable, "-c", script, "5"]

        with patch.object(backend, "clone_arguments", side_effect=slow_arguments):
            job_id = backend.clone_start("example", "cancelled", "full")["id"]
            backend.clone_cancel(job_id)
            cancelled = wait_for(job_id)
        self.assertTrue(cancelled["cancelled"])
        self.assertFalse((self.projects / "cancelled").exists())
        self.assertFalse(list(self.projects.glob(".zephyrus-clone-*")))

    def test_managed_command_times_out(self):
        with self.assertRaisesRegex(ValueError, "timed out"):
            backend.run_managed([sys.executable, "-c", "import time; time.sleep(3)"], timeout=0.1)

    def test_projects_root_reads_xdg_user_dir(self):
        del os.environ["XDG_PROJECTS_DIR"]
        config = self.home / "config"
        config.mkdir()
        (config / "user-dirs.dirs").write_text('XDG_PROJECTS_DIR="$HOME/Work"\n')
        self.assertEqual(backend.projects_root(), self.projects)

    def test_template_catalogue_matches_syntaxis_categories(self):
        catalogue = backend.template_catalogue()
        self.assertEqual(len(catalogue), 30)
        self.assertEqual(
            {item["category"] for item in catalogue}, {"Basics", "Web", "Backend", "Native"}
        )
        self.assertFalse(any("command" in item for item in catalogue))

    def test_bootstrap_infers_tools_and_notes_are_private(self):
        project = self.projects / "sample"
        project.mkdir()
        (project / "Cargo.toml").write_text("[package]\nname='sample'\n")
        self.assertEqual(backend.bootstrap_plan(str(project))["tools"], ["rust@stable"])
        with patch.object(backend.shutil, "which", return_value="/usr/bin/mise"):
            result = backend.prepare_mise(str(project), "bootstrap")
        self.assertIn(
            "mise use --yes --env local rust@stable", Path(result["setupScript"]).read_text()
        )
        (project / "mise.toml").write_text("[tools]\nrust='stable'\n")
        self.assertTrue(backend.bootstrap_plan(str(project))["configured"])
        backend.save_notes(str(project), "Keep this in mind")
        self.assertEqual(backend.load_notes(str(project))["notes"], "Keep this in mind")
        self.assertFalse((project / "notes.txt").exists())

    def test_cleanup_revalidates_selected_ignored_entries(self):
        project = self.projects / "sample"
        project.mkdir()
        (project / ".git").mkdir()
        with (
            patch.object(backend.shutil, "which", return_value="/usr/bin/git"),
            patch.object(backend, "run_managed") as command,
        ):
            command.return_value = backend.subprocess.CompletedProcess(
                [], 0, "Would remove target/\n", ""
            )
            preview = backend.cleanup_preview(str(project))
            self.assertEqual(preview, [{"path": "target", "directory": True}])
            with self.assertRaises(ValueError):
                backend.cleanup_selected(str(project), [".env"])
            backend.cleanup_selected(str(project), ["target"])
        self.assertIn("--", command.call_args.args[0])

    def test_trash_requires_exact_project_name(self):
        project = self.projects / "sample"
        project.mkdir()
        backend.list_projects()
        self.assertIn(str(project), backend.read_profiles())
        with self.assertRaises(ValueError):
            backend.trash_project(str(project), "wrong")
        with (
            patch.object(backend.shutil, "which", return_value="/usr/bin/gio"),
            patch.object(backend, "run_managed") as command,
        ):
            command.return_value = backend.subprocess.CompletedProcess([], 0, "", "")
            backend.trash_project(str(project), "sample")
        self.assertEqual(command.call_args.args[0], ["/usr/bin/gio", "trash", "--", str(project)])
        self.assertNotIn(str(project), backend.read_profiles())

    def test_free_space_preserves_projects_and_requires_tool_confirmation(self):
        npm_cache = self.home / ".npm/_cacache"
        uv_cache = self.home / "cache/uv"
        mise_install = self.home / ".local/share/mise/installs/node/24"
        bun_install = self.home / ".bun/bin"
        for directory in (npm_cache, uv_cache, mise_install, bun_install):
            directory.mkdir(parents=True)
        project = self.projects / "keep"
        project.mkdir()
        with self.assertRaises(ValueError):
            backend.free_space(False, False, True)
        self.assertIn("Removed 2", backend.free_space(True, False, False)["output"])
        self.assertFalse(npm_cache.exists())
        self.assertFalse(uv_cache.exists())
        self.assertTrue(mise_install.exists())
        self.assertTrue(bun_install.exists())
        self.assertTrue(project.exists())

        with (
            patch.object(backend.shutil, "which", return_value="/usr/bin/mise"),
            patch.object(backend, "run_managed") as command,
        ):
            command.return_value = backend.subprocess.CompletedProcess([], 0, "", "")
            backend.free_space(False, True, True, "REMOVE TOOLS")
        self.assertEqual(command.call_count, 2)
        self.assertEqual(
            command.call_args_list[0].args[0], ["/usr/bin/mise", "uninstall", "--all", "--yes"]
        )
        self.assertFalse(bun_install.exists())
        self.assertTrue(project.exists())

    def test_free_space_refuses_redirected_cache_parent(self):
        outside = self.home.parent / (self.home.name + "-outside")
        outside.mkdir()
        self.addCleanup(lambda: outside.rmdir())
        cache = outside / "_cacache"
        cache.mkdir()
        self.addCleanup(lambda: cache.rmdir())
        (self.home / ".npm").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "unsafe path"):
            backend.free_space(True, False, False)
        self.assertTrue(cache.exists())


if __name__ == "__main__":
    unittest.main()
