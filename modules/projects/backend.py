"""Local project catalogue and actions for the Projects space."""

import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from modules.projects.templates import BY_ID, TEMPLATES
from services.storage import atomic_write

ICON_CANDIDATES = (
    "favicon.svg",
    "favicon.png",
    "favicon.ico",
    "public/favicon.svg",
    "public/favicon.png",
    "public/favicon.ico",
    "app/icon.svg",
    "app/icon.png",
    "src/favicon.svg",
    "assets/icon.svg",
    "assets/icon.png",
    "assets/logo.svg",
    "assets/logo.png",
    ".idea/icon.svg",
)
IMAGE_SUFFIXES = {".svg", ".png", ".ico"}
_running = set()
_incomplete = set()
_run_lock = threading.Lock()
_clone_jobs = {}
_profile_lock = threading.Lock()


def _stop_worker(signum, _frame):
    with _run_lock:
        children = list(_running)
        incomplete = list(_incomplete)
    for child in children:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for child in children:
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    for path in incomplete:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path, ignore_errors=True)
    os._exit(128 + signum)


def run_managed(command, *, cwd=None, timeout):
    child = subprocess.Popen(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    with _run_lock:
        _running.add(child)
    try:
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.communicate()
            raise ValueError("The operation timed out. Try again.") from error
        return subprocess.CompletedProcess(command, child.returncode, stdout, stderr)
    finally:
        with _run_lock:
            _running.discard(child)


def projects_root():
    home = Path.home()
    configured = os.environ.get("XDG_PROJECTS_DIR", "").strip()
    if not configured:
        user_dirs = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "user-dirs.dirs"
        try:
            for line in user_dirs.read_text().splitlines():
                match = re.fullmatch(r'\s*XDG_PROJECTS_DIR="(\$HOME/[^"\n]*|/[^"\n]*)"\s*', line)
                if match:
                    configured = match.group(1)
                    break
        except OSError:
            pass
    configured = configured.replace("$HOME", str(home), 1)
    root = Path(configured).expanduser() if configured else home / "Projects"
    if not root.is_absolute():
        raise ValueError("XDG_PROJECTS_DIR must be an absolute path.")
    return root


def history_path():
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return base / "zephyrus-shell" / "projects.json"


def profiles_path():
    return history_path().parent / "project-profiles.json"


def read_profiles():
    """Read saved technology detections; ignore damaged individual entries."""
    path = profiles_path()
    try:
        if path.stat().st_size > 8 * 1024 * 1024:
            return {}
        data = json.loads(path.read_text())
        if data.get("version") != 1 or not isinstance(data.get("projects"), dict):
            return {}
    except (OSError, ValueError, TypeError, AttributeError):
        return {}
    profiles = {}
    for path, profile in data["projects"].items():
        if not isinstance(path, str) or not isinstance(profile, dict):
            continue
        device, inode, badges = (profile.get("device"), profile.get("inode"), profile.get("badges"))
        if (
            not isinstance(device, int)
            or isinstance(device, bool)
            or not isinstance(inode, int)
            or isinstance(inode, bool)
            or not isinstance(badges, list)
            or len(badges) > 6
        ):
            continue
        if not all(
            isinstance(badge, dict)
            and isinstance(badge.get("icon"), str)
            and re.fullmatch(r"[a-z0-9-]+", badge["icon"])
            and isinstance(badge.get("label"), str)
            and 0 < len(badge["label"]) <= 64
            for badge in badges
        ):
            continue
        profiles[path] = {"device": device, "inode": inode, "badges": badges}
    return profiles


def write_profiles(profiles):
    atomic_write(profiles_path(), json.dumps({"version": 1, "projects": profiles}))


def detected_profile(project):
    stat = project.stat()
    return {"device": stat.st_dev, "inode": stat.st_ino, "badges": technologies(project)}


def read_history():
    try:
        data = json.loads(history_path().read_text())
        if data.get("version") == 1 and isinstance(data.get("opened"), dict):
            return {
                key: value
                for key, value in data["opened"].items()
                if isinstance(key, str) and isinstance(value, int) and value >= 0
            }
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return {}


def read_syntaxis_history():
    """Use existing Syntaxis open times when present, without requiring it."""
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    path = base / "syntaxis" / "workspaces.json"
    try:
        if path.stat().st_size > 4 * 1024 * 1024:
            return {}
        data = json.loads(path.read_text())
        return {
            entry["root"]: entry["last_opened_unix_ms"]
            for entry in data.get("workspaces", [])
            if isinstance(entry, dict)
            and isinstance(entry.get("root"), str)
            and isinstance(entry.get("last_opened_unix_ms"), int)
        }
    except (OSError, ValueError, TypeError, AttributeError):
        return {}


def write_history(opened):
    atomic_write(history_path(), json.dumps({"version": 1, "opened": opened}))


def read_manifest(path, limit=256 * 1024):
    try:
        if path.is_file() and path.stat().st_size <= limit:
            return path.read_text(errors="replace")
    except OSError:
        pass
    return ""


def package_dependencies(root):
    try:
        package = json.loads(read_manifest(root / "package.json"))
        if not isinstance(package, dict):
            return set()
        return set(package.get("dependencies", {})) | set(package.get("devDependencies", {}))
    except (ValueError, TypeError):
        return set()


def technologies(root):
    """Detect a bounded set of badges from root-level manifests and markers."""
    found = []

    def add(icon, label):
        if icon not in {entry["icon"] for entry in found}:
            found.append({"icon": icon, "label": label})

    def any_file(*names):
        return any((root / name).exists() for name in names)

    dependencies = package_dependencies(root)
    if any_file("bun.lock", "bun.lockb"):
        add("bun", "Bun")
    elif any_file("pnpm-lock.yaml"):
        add("pnpm", "pnpm")
    elif any_file("yarn.lock"):
        add("yarn", "Yarn")
    elif any_file("package.json"):
        add("npm", "npm")
    if any_file("deno.json", "deno.jsonc", "deno.lock"):
        add("denojs", "Deno")
    if any_file("package.json"):
        add("nodejs", "Node.js")
    for dependency, icon, label in (
        ("next", "nextjs", "Next.js"),
        ("react", "react", "React"),
        ("vue", "vuejs", "Vue"),
        ("svelte", "svelte", "Svelte"),
        ("@angular/core", "angular", "Angular"),
        ("astro", "astro", "Astro"),
        ("vite", "vitejs", "Vite"),
        ("tailwindcss", "tailwindcss", "Tailwind CSS"),
        ("prisma", "prisma", "Prisma"),
        ("@prisma/client", "prisma", "Prisma"),
        ("typescript", "typescript", "TypeScript"),
    ):
        if dependency in dependencies:
            add(icon, label)
    if any_file("tsconfig.json", "tsconfig.base.json"):
        add("typescript", "TypeScript")
    if any_file("vite.config.ts", "vite.config.js", "vite.config.mjs"):
        add("vitejs", "Vite")
    if any_file("tailwind.config.ts", "tailwind.config.js", "tailwind.config.cjs"):
        add("tailwindcss", "Tailwind CSS")
    for marker, icon, label in (
        ("Cargo.toml", "rust", "Rust"),
        ("go.mod", "go", "Go"),
        ("pyproject.toml", "python", "Python"),
        ("requirements.txt", "python", "Python"),
        ("Dockerfile", "docker", "Docker"),
        ("compose.yaml", "docker", "Docker"),
        ("docker-compose.yml", "docker", "Docker"),
        ("composer.json", "composer", "Composer"),
        ("manage.py", "django", "Django"),
        ("main.tf", "terraform", "Terraform"),
        ("firebase.json", "firebase", "Firebase"),
    ):
        if (root / marker).exists():
            add(icon, label)
    pyproject = read_manifest(root / "pyproject.toml")
    if "fastapi" in pyproject.lower():
        add("fastapi", "FastAPI")
    if "dioxus" in read_manifest(root / "Cargo.toml").lower():
        add("rust", "Rust")
    if (root / ".git").exists() and not found:
        add("git", "Git")
    return found[:6]


def project_logo(root):
    for relative in ICON_CANDIDATES:
        candidate = root / relative
        try:
            if (
                candidate.suffix in IMAGE_SUFFIXES
                and not candidate.is_symlink()
                and candidate.is_file()
                and candidate.stat().st_size <= 256 * 1024
            ):
                return candidate.as_uri()
        except OSError:
            pass
    return ""


def list_projects(rescan_profiles=False):
    root = projects_root()
    if not root.is_dir():
        return {
            "root": str(root),
            "projects": [],
            "missing": True,
            "mise": bool(shutil.which("mise")),
            "templates": template_catalogue(),
        }
    opened = read_history()
    prior = read_syntaxis_history()
    projects = []
    try:
        children = list(root.iterdir())
    except OSError as error:
        raise ValueError(f"Cannot read Projects: {error.strerror or error}") from error
    warning = ""
    with _profile_lock:
        profiles = read_profiles()
        changed = False
        for child in children:
            try:
                if child.name.startswith(".") or child.is_symlink() or not child.is_dir():
                    continue
                path = str(child.resolve())
                stat = child.stat()
                profile = profiles.get(path)
                if (
                    rescan_profiles
                    or profile is None
                    or profile["device"] != stat.st_dev
                    or profile["inode"] != stat.st_ino
                ):
                    profile = detected_profile(child)
                    profiles[path] = profile
                    changed = True
                badges = profile["badges"]
                projects.append(
                    {
                        "name": child.name,
                        "path": path,
                        "logo": project_logo(child),
                        "symbol": badges[0]["icon"] if badges else "",
                        "badges": badges,
                        "opened": max(opened.get(path, 0), prior.get(path, 0)),
                    }
                )
            except OSError:
                continue
        if changed:
            try:
                write_profiles(profiles)
            except OSError:
                warning = "Project technologies could not be saved. Check the XDG data directory."
    projects.sort(key=lambda item: (-float(item["opened"]), str(item["name"]).casefold()))
    return {
        "root": str(root),
        "projects": projects,
        "missing": False,
        "mise": bool(shutil.which("mise")),
        "templates": template_catalogue(),
        "warning": warning,
    }


def refresh_profile(value):
    project = checked_project(value)
    with _profile_lock:
        profiles = read_profiles()
        profile = detected_profile(project)
        profiles[str(project)] = profile
        write_profiles(profiles)
    return {"badges": profile["badges"]}


def template_catalogue():
    return [
        {
            **{key: value for key, value in template.items() if key != "command"},
            "available": not template["requires"] or bool(shutil.which(template["requires"])),
        }
        for template in TEMPLATES
    ]


def valid_project_name(value):
    name = value.strip()
    if (
        not name
        or name in {".", ".."}
        or len(name.encode()) > 255
        or "/" in name
        or "\\" in name
        or any(ord(char) < 32 for char in name)
    ):
        raise ValueError("Use a single folder name without slashes or control characters.")
    return name


def destination_for(name):
    root = projects_root()
    root.mkdir(parents=True, exist_ok=True)
    if not root.is_dir():
        raise ValueError("Projects is not a folder.")
    destination = root / valid_project_name(name)
    if destination.exists() or destination.is_symlink():
        raise ValueError("A project with that name already exists.")
    return destination


def checked_project(value):
    root = projects_root().resolve(strict=True)
    if Path(value).is_symlink():
        raise ValueError("Select a project inside the XDG Projects directory.")
    path = Path(value).resolve(strict=True)
    if path.parent != root or not path.is_dir():
        raise ValueError("Select a project inside the XDG Projects directory.")
    return path


def open_project(value):
    path = checked_project(value)
    zed = shutil.which("zed") or shutil.which("zeditor")
    if not zed:
        raise ValueError("Zed (zed or zeditor) is not installed or is not on PATH.")
    subprocess.Popen(
        [zed, str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    opened = read_history()
    opened[str(path)] = int(time.time() * 1000)
    try:
        write_history(opened)
    except OSError:
        # The editor already launched; a read-only data directory must not turn
        # that successful action into a misleading failure.
        pass
    return {"path": str(path)}


def create_project(name, template):
    if template not in BY_ID:
        raise ValueError("Choose a supported project starter.")
    destination = destination_for(name)
    selected = BY_ID[template]
    if selected["command"] and template != "vite-plus" and not shutil.which("mise"):
        raise ValueError("Install mise to use this project starter.")
    if selected["requires"] and not shutil.which(selected["requires"]):
        raise ValueError(f"{selected['requires']} is required for this starter.")
    destination.mkdir()
    result = {"path": str(destination), "name": destination.name, "template": selected["label"]}
    if selected["command"]:
        try:
            result.update(prepare_setup(destination, selected["command"]))
        except OSError:
            destination.rmdir()
            raise
    return result


def setup_root():
    base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return base / "zephyrus-shell" / "project-setup"


def prepare_setup(project, command):
    """Create a private script for the embedded interactive terminal."""
    token = uuid.uuid4().hex
    directory = setup_root()
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    cutoff = time.time() - 24 * 60 * 60
    for old in directory.iterdir():
        try:
            if (
                re.fullmatch(r"[0-9a-f]{32}\.(?:sh|status)", old.name)
                and old.stat().st_mtime < cutoff
            ):
                old.unlink()
        except OSError:
            pass
    script = directory / f"{token}.sh"
    status = directory / f"{token}.status"
    contents = (
        "#!/usr/bin/env bash\n"
        f"cd -- {shlex.quote(str(project))} || exit 1\n"
        f"{command}\n"
        "result=$?\n"
        f"printf '%s\\n' \"$result\" > {shlex.quote(str(status))}\n"
        "if [ \"$result\" -eq 0 ]; then printf '\\nSetup finished successfully.\\n'; "
        "else printf '\\nSetup exited with code %s.\\n' \"$result\"; fi\n"
        'exec "${SHELL:-/bin/bash}" -i\n'
    )
    with script.open("x") as output:
        output.write(contents)
    script.chmod(0o700)
    return {"setupId": token, "setupScript": str(script)}


def setup_status(value):
    if not re.fullmatch(r"[0-9a-f]{32}", value):
        raise ValueError("Invalid setup session.")
    directory = setup_root()
    status = directory / f"{value}.status"
    try:
        code = int(status.read_text().strip())
    except FileNotFoundError:
        return {"done": False}
    except (OSError, ValueError) as error:
        raise ValueError("Could not read project setup status.") from error
    status.unlink(missing_ok=True)
    (directory / f"{value}.sh").unlink(missing_ok=True)
    return {"done": True, "success": code == 0, "exitCode": code}


def discard_setup(value):
    if not re.fullmatch(r"[0-9a-f]{32}", value):
        raise ValueError("Invalid setup session.")
    directory = setup_root()
    (directory / f"{value}.sh").unlink(missing_ok=True)
    (directory / f"{value}.status").unlink(missing_ok=True)
    return {"discarded": True}


MISE_CONFIGS = ("mise.toml", ".mise.toml", "mise.local.toml", ".mise.local.toml", ".tool-versions")


def inferred_tools(project):
    def has(*names):
        return any((project / name).exists() for name in names)

    tools = []

    def add(tool):
        if tool not in tools:
            tools.append(tool)

    if has("Cargo.toml", "rust-toolchain", "rust-toolchain.toml"):
        add("rust@stable")
    if has("deno.json", "deno.jsonc", "deno.lock"):
        add("deno@latest")
    elif has("bun.lock", "bun.lockb"):
        add("bun@latest")
    elif has("package.json"):
        add("node@lts")
        if has("pnpm-lock.yaml"):
            add("pnpm@latest")
        elif has("yarn.lock"):
            add("yarn@latest")
    if has("pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile"):
        add("python@latest")
        if has("uv.lock"):
            add("uv@latest")
    if has("go.mod", "go.work"):
        add("go@latest")
    if has("global.json") or any(path.suffix in {".csproj", ".sln"} for path in project.iterdir()):
        add("dotnet@latest")
    if has("pom.xml", "build.gradle", "build.gradle.kts", "gradlew"):
        add("java@latest")
    if has("Gemfile", ".ruby-version"):
        add("ruby@latest")
    if has("composer.json"):
        add("php@latest")
        add("composer@latest")
    if has("main.tf", ".terraform.lock.hcl"):
        add("terraform@latest")
    if has("Justfile", "justfile"):
        add("just@latest")
    return tools


def bootstrap_plan(value):
    project = checked_project(value)
    configured = any((project / name).is_file() for name in MISE_CONFIGS)
    return {"configured": configured, "tools": [] if configured else inferred_tools(project)}


def _exclude_local_mise(project):
    git = shutil.which("git")
    if not git:
        return
    output = subprocess.run(
        [git, "rev-parse", "--git-path", "info/exclude"],
        cwd=project,
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    if output.returncode:
        return
    path = Path(output.stdout.strip())
    if not path.is_absolute():
        path = project / path
    path.parent.mkdir(parents=True, exist_ok=True)
    current = path.read_text() if path.exists() else ""
    additions = [
        name for name in ("mise.local.toml", "mise.local.lock") if name not in current.splitlines()
    ]
    if additions:
        with path.open("a") as destination:
            if current and not current.endswith("\n"):
                destination.write("\n")
            destination.write("\n".join(additions) + "\n")


def prepare_mise(value, action, tools=""):
    project = checked_project(value)
    if not shutil.which("mise"):
        raise ValueError("Install mise to manage project tools.")
    if action == "bootstrap":
        plan = bootstrap_plan(str(project))
        if plan["configured"]:
            command = "mise trust --yes && mise install --yes"
        else:
            selected = tools.split() if tools.strip() else plan["tools"]
            if not selected:
                raise ValueError("Enter at least one mise tool to bootstrap this project.")
            if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@:._+/-]*", tool) for tool in selected):
                raise ValueError("Use valid mise tool names and versions.")
            _exclude_local_mise(project)
            command = shlex.join(["mise", "use", "--yes", "--env", "local", *selected])
    elif action == "update":
        command = "mise trust --yes && mise upgrade --local"
    else:
        raise ValueError("Unsupported mise action.")
    return prepare_setup(project, command)


def notes_path(project):
    key = hashlib.sha256(str(project).encode()).hexdigest()
    return history_path().parent / "projects" / "notes" / f"{key}.txt"


def load_notes(value):
    project = checked_project(value)
    path = notes_path(project)
    try:
        if path.stat().st_size > 256 * 1024:
            raise ValueError("Project notes are too large to open.")
        return {"notes": path.read_text()}
    except FileNotFoundError:
        return {"notes": ""}


def save_notes(value, notes):
    project = checked_project(value)
    if not isinstance(notes, str) or len(notes.encode()) > 256 * 1024:
        raise ValueError("Project notes must be smaller than 256 KiB.")
    atomic_write(notes_path(project), notes)
    return {"message": "Project notes saved."}


CLEAN_EXCLUSIONS = (".env", ".env.*", ".envrc", ".direnv/", "*.local", "*.local.*")


def cleanup_command(preview, selected=()):
    # Selected names are literal paths, never globs or pathspec magic.
    args = ["git", "-c", "core.quotePath=false", "--literal-pathspecs", "clean"]
    args.append("-ndX" if preview else "-fdX")
    for exclusion in CLEAN_EXCLUSIONS:
        args.extend(["-e", exclusion])
    if selected:
        args.extend(["--", *selected])
    return args


def cleanup_preview(value):
    project = checked_project(value)
    if not shutil.which("git") or not (project / ".git").exists():
        raise ValueError("Cleanup requires a Git project.")
    result = run_managed(cleanup_command(True), cwd=project, timeout=30)
    if result.returncode:
        raise ValueError("Git could not inspect ignored project files.")
    return [
        {"path": line.removeprefix("Would remove ").rstrip("/"), "directory": line.endswith("/")}
        for line in result.stdout.splitlines()
        if line.startswith("Would remove ")
    ]


def cleanup_selected(value, selected):
    project = checked_project(value)
    if not isinstance(selected, list) or not selected:
        raise ValueError("Select at least one cleanup entry.")
    available = {entry["path"] for entry in cleanup_preview(str(project))}
    if any(not isinstance(path, str) or path not in available for path in selected):
        raise ValueError("The cleanup selection is no longer valid.")
    unique = list(dict.fromkeys(selected))
    result = run_managed(cleanup_command(False, unique), cwd=project, timeout=120)
    if result.returncode:
        raise ValueError("Git could not clean the selected project files.")
    return {"count": len(unique)}


def trash_project(value, confirmation):
    project = checked_project(value)
    if confirmation != project.name:
        raise ValueError("Type the project name to confirm.")
    gio = shutil.which("gio")
    trash = shutil.which("trash-put")
    if not gio and not trash:
        raise ValueError("Install gio or trash-cli to move projects to Trash.")
    command = [gio, "trash", "--", str(project)] if gio else [trash, "--", str(project)]
    result = run_managed(command, timeout=30)
    if result.returncode:
        raise ValueError("The project could not be moved to Trash.")
    opened = read_history()
    opened.pop(str(project), None)
    try:
        write_history(opened)
    except OSError:
        pass
    notes_path(project).unlink(missing_ok=True)
    with _profile_lock:
        profiles = read_profiles()
        if profiles.pop(str(project), None) is not None:
            try:
                write_profiles(profiles)
            except OSError:
                pass
    return {"message": f"Moved {project.name} to Trash."}


def mise_global(action):
    mise = shutil.which("mise")
    if not mise:
        raise ValueError("Install mise to manage tools.")
    commands = {
        "update": [[mise, "upgrade", "--inactive", "--yes"]],
        "prune": [[mise, "prune", "--tools", "--yes"]],
    }
    if action not in commands:
        raise ValueError("Unsupported mise action.")
    output = []
    for command in commands[action]:
        result = run_managed(command, cwd=Path.home(), timeout=600)
        output.append((result.stdout + result.stderr)[-2500:])
        if result.returncode:
            raise ValueError(output[-1].strip() or "Mise could not finish the action.")
    return {"message": "Mise action completed.", "output": "\n".join(output).strip()}


CACHE_ROOTS = (
    ".npm/_cacache",
    ".npm/_logs",
    ".npm/_npx",
    ".bun/install/cache",
    ".cargo/registry/cache",
    ".cargo/registry/src",
    ".cargo/registry/index",
    ".cargo/git/checkouts",
    ".cargo/git/db",
    ".rustup/downloads",
    ".rustup/tmp",
    ".local/share/mise/downloads",
    ".local/share/pnpm/store",
    ".gradle/caches",
    ".gradle/daemon",
    ".gradle/native",
    ".gradle/notifications",
    ".gradle/wrapper/dists",
    ".nuget/packages",
    ".pnpm-store",
    ".yarn/cache",
    ".yarn/unplugged",
    "go/pkg/mod",
    "go/pkg/sumdb",
)
XDG_CACHE_TOOLS = (
    "bun",
    "cargo",
    "deno",
    "go-build",
    "gradle",
    "mise",
    "npm",
    "pip",
    "pnpm",
    "rustup",
    "uv",
    "yarn",
)
TOOL_ROOTS = (".bun", ".deno", ".rustup")


def purge_known(paths, extra_roots=()):
    """Remove only named reinstallable paths within known data roots."""
    home = Path.home().resolve(strict=True)
    if not home.is_dir() or home == home.parent:
        raise ValueError("The home directory is not safe to clean.")
    allowed = (home, *(root.resolve(strict=True) for root in extra_roots))
    removed = 0
    for path in paths:
        if not (path.exists() or path.is_symlink()):
            continue
        try:
            parent = path.parent.resolve(strict=True)
            if not any(parent.is_relative_to(root) for root in allowed):
                raise ValueError(f"Refused to clean an unsafe path: {path}")
            if path.is_symlink():
                path.unlink()
            else:
                resolved = path.resolve(strict=True)
                if resolved in allowed or not any(
                    resolved.is_relative_to(root) for root in allowed
                ):
                    raise ValueError(f"Refused to clean an unsafe path: {path}")
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            removed += 1
        except OSError as error:
            raise ValueError(f"Could not remove {path}: {error}") from error
    return removed


def free_space(caches, mise_tools, other_tools, confirmation=""):
    if not all(isinstance(choice, bool) for choice in (caches, mise_tools, other_tools)):
        raise ValueError("Choose which runtime data to remove.")
    if not any((caches, mise_tools, other_tools)):
        raise ValueError("Select at least one cleanup option.")
    if (mise_tools or other_tools) and confirmation != "REMOVE TOOLS":
        raise ValueError("Type REMOVE TOOLS to confirm tool removal.")
    mise = shutil.which("mise") if mise_tools else None
    if mise_tools and not mise:
        raise ValueError("Mise is unavailable; installed Mise tools were not removed.")
    messages = []
    if caches:
        home = Path.home()
        xdg_cache = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache")).expanduser()
        if not xdg_cache.is_absolute() or xdg_cache.resolve() in {Path("/"), home.resolve()}:
            raise ValueError("XDG_CACHE_HOME must be an absolute cache directory.")
        if xdg_cache.exists() and (
            not xdg_cache.is_dir() or xdg_cache.stat().st_uid != os.getuid()
        ):
            raise ValueError("XDG_CACHE_HOME must be a cache directory owned by this user.")
        paths = [home / name for name in CACHE_ROOTS]
        paths.extend(xdg_cache / name for name in XDG_CACHE_TOOLS)
        count = purge_known(paths, (xdg_cache,) if xdg_cache.exists() else ())
        messages.append(f"Removed {count} development cache locations.")
    if mise_tools:
        for command in ([mise, "uninstall", "--all", "--yes"], [mise, "cache", "clear"]):
            result = run_managed(command, cwd=Path.home(), timeout=600)
            if result.returncode:
                raise ValueError(
                    (result.stderr or result.stdout).strip()[-500:]
                    or "Mise could not remove installed tools."
                )
        messages.append("Removed installed Mise tools and its cache.")
    if other_tools:
        count = purge_known([Path.home() / name for name in TOOL_ROOTS])
        messages.append(f"Removed {count} other developer tool locations.")
    return {"message": "Runtime cleanup completed.", "output": "\n".join(messages)}


def clone_arguments(url, name, mode):
    url = url.strip()
    parsed = urlparse(url)
    if not (
        (
            parsed.scheme in {"https", "http", "ssh", "git"}
            and parsed.hostname
            and parsed.path.strip("/")
        )
        or re.fullmatch(r"git@[^:\s]+:.+", url)
    ):
        raise ValueError("Enter an HTTPS, SSH, or Git repository URL.")
    if mode not in {"full", "blobless", "shallow"}:
        raise ValueError("Choose a supported clone mode.")
    flags = {"full": [], "blobless": ["--filter=blob:none"], "shallow": ["--depth=1"]}[mode]
    destination = destination_for(name)
    git = shutil.which("git")
    if not git:
        raise ValueError("Git is not installed or is not on PATH.")
    return url, destination, [git, "clone", *flags, "--progress", "--", url]


def _clone_job(job_id, command, destination, staging):
    build = staging / destination.name
    child = None
    lines = []
    try:
        with _run_lock:
            if _clone_jobs[job_id]["cancelled"]:
                return
        child = subprocess.Popen(
            [*command, str(build)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            bufsize=1,
        )
        with _run_lock:
            _running.add(child)
            _clone_jobs[job_id]["process"] = child
            cancelled = _clone_jobs[job_id]["cancelled"]
        if cancelled:
            os.killpg(child.pid, signal.SIGTERM)
        assert child.stderr is not None
        for line in child.stderr:
            line = line.strip()
            if not line:
                continue
            lines.append(line)
            lines = lines[-8:]
            match = re.search(r"(Counting|Compressing|Receiving|Resolving) objects:\s*(\d+)%", line)
            with _run_lock:
                _clone_jobs[job_id]["phase"] = (
                    (match.group(1) + " objects") if match else "Cloning repository"
                )
                _clone_jobs[job_id]["percent"] = int(match.group(2)) if match else None
        code = child.wait()
        with _run_lock:
            cancelled = _clone_jobs[job_id]["cancelled"]
        if cancelled:
            return
        if code:
            raise ValueError(
                "Git clone failed. " + (lines[-1] if lines else "Check the URL and credentials.")
            )
        if destination.exists() or destination.is_symlink():
            raise ValueError("A project with that name already exists.")
        build.rename(destination)
        with _run_lock:
            _clone_jobs[job_id].update(
                done=True, path=str(destination), phase="Complete", percent=100
            )
    except (OSError, ValueError) as error:
        with _run_lock:
            _clone_jobs[job_id].update(done=True, error=str(error))
    finally:
        if child:
            if child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    child.wait()
            if child.stderr:
                child.stderr.close()
            with _run_lock:
                _running.discard(child)
                _clone_jobs[job_id]["process"] = None
        shutil.rmtree(staging, ignore_errors=True)
        with _run_lock:
            _incomplete.discard(staging)
            _clone_jobs[job_id]["done"] = True


def clone_start(url, name, mode):
    url, destination, command = clone_arguments(url, name, mode)
    staging = Path(tempfile.mkdtemp(prefix=".zephyrus-clone-", dir=destination.parent))
    job_id = uuid.uuid4().hex
    with _run_lock:
        _incomplete.add(staging)
        _clone_jobs[job_id] = {
            "id": job_id,
            "phase": "Preparing clone",
            "percent": None,
            "done": False,
            "cancelled": False,
            "error": "",
            "path": "",
            "process": None,
        }
    threading.Thread(
        target=_clone_job,
        args=(job_id, command, destination, staging),
        name="project-clone",
        daemon=True,
    ).start()
    return {"id": job_id}


def clone_status(job_id):
    with _run_lock:
        job = _clone_jobs.get(job_id)
        if not job:
            raise ValueError("Clone session was not found.")
        return {key: value for key, value in job.items() if key != "process"}


def clone_cancel(job_id):
    with _run_lock:
        job = _clone_jobs.get(job_id)
        if not job:
            raise ValueError("Clone session was not found.")
        job["cancelled"] = True
        child = job["process"]
    if child:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    return {"cancelled": True}


def run(request):
    operation = request.get("op")
    if operation == "list":
        return list_projects()
    if operation == "refreshAllProfiles":
        return list_projects(rescan_profiles=True)
    if operation == "refreshProfile":
        return refresh_profile(request.get("path", ""))
    if operation == "open":
        return open_project(request.get("path", ""))
    if operation == "create":
        return create_project(request.get("name", ""), request.get("template", "empty"))
    if operation == "cloneStart":
        return clone_start(
            request.get("url", ""), request.get("name", ""), request.get("mode", "full")
        )
    if operation == "cloneStatus":
        return clone_status(request.get("job", ""))
    if operation == "cloneCancel":
        return clone_cancel(request.get("job", ""))
    if operation == "setupStatus":
        return setup_status(request.get("setupId", ""))
    if operation == "discardSetup":
        return discard_setup(request.get("setupId", ""))
    if operation == "bootstrapPlan":
        return bootstrap_plan(request.get("path", ""))
    if operation == "prepareMise":
        return prepare_mise(
            request.get("path", ""), request.get("action", ""), request.get("tools", "")
        )
    if operation == "notes":
        return load_notes(request.get("path", ""))
    if operation == "saveNotes":
        return save_notes(request.get("path", ""), request.get("notes", ""))
    if operation == "cleanupPreview":
        return {"entries": cleanup_preview(request.get("path", ""))}
    if operation == "cleanup":
        return cleanup_selected(request.get("path", ""), request.get("selected", []))
    if operation == "trash":
        return trash_project(request.get("path", ""), request.get("confirmation", ""))
    if operation == "miseGlobal":
        return mise_global(request.get("action", ""))
    if operation == "freeSpace":
        return free_space(
            request.get("caches"),
            request.get("miseTools"),
            request.get("otherTools"),
            request.get("confirmation", ""),
        )
    raise ValueError("Unsupported project action.")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _stop_worker)
    from services.worker import serve

    serve(
        run,
        latest=("list",),
        controls=(
            "refreshAllProfiles",
            "refreshProfile",
            "open",
            "create",
            "cloneStart",
            "prepareMise",
            "discardSetup",
            "saveNotes",
            "cleanup",
            "trash",
            "miseGlobal",
            "freeSpace",
        ),
    )
