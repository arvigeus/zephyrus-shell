#!/usr/bin/env python3
"""Offline production QML workloads and Linux process measurements for autoresearch."""

import argparse
import hashlib
import json
import os
import platform
import signal
import socket
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHASES = ("desktop", "apps", "released")
PROFILE_FEATURES = "binding,creating,handlingsignal,compiling"


def desktop_entry(index):
    return (
        "[Desktop Entry]\nType=Application\n"
        f"Name=Fixture App {index}\nGenericName={'Editor' if index % 2 else 'Browser'}\n"
        "Exec=/bin/false\nKeywords=Internet;Graphics;\nCategories=Utility;\n"
    )


def workload_signature():
    fixture = (ROOT / "performance.qml").read_bytes()
    entries = "".join(desktop_entry(index) for index in range(300)).encode()
    return hashlib.sha256(fixture + entries).hexdigest()


def processes(group):
    result = {}
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():
            continue
        try:
            stat = (path / "stat").read_text().rsplit(")", 1)[1].split()
            if int(stat[2]) != group:
                continue
            status = (path / "status").read_text()
            name = (path / "comm").read_text().strip()
            switches = sum(
                int(line.split()[1]) for line in status.splitlines() if "ctxt_switches:" in line
            )
            result[int(path.name)] = {
                "name": name,
                "rss_kib": int(stat[21]) * os.sysconf("SC_PAGE_SIZE") / 1024,
                "cpu_ticks": int(stat[11]) + int(stat[12]),
                "switches": switches,
            }
        except (OSError, ValueError, IndexError):
            continue
    return result


def resource_summary(samples):
    # Let each phase settle before taking CPU and context-switch deltas.
    stable = [
        sample
        for sample in samples
        if sample[0] - samples[0][0] >= 0.3
        and any(proc["name"] == "quickshell" for proc in sample[1].values())
    ]
    if len(stable) < 2:
        raise RuntimeError("Resource phase ended before it could be sampled")
    first_time, first = stable[0]
    last_time, last = stable[-1]
    elapsed = last_time - first_time
    common = first.keys() & last.keys()
    shell = {pid for pid in common if last[pid]["name"] == "quickshell"}
    if len(shell) != 1:
        raise RuntimeError("Expected exactly one benchmark shell")
    return {
        "tree_rss_kib": statistics.median(
            sum(proc["rss_kib"] for proc in procs.values()) for _, procs in stable
        ),
        "shell_cpu_pct": round(
            sum(last[pid]["cpu_ticks"] - first[pid]["cpu_ticks"] for pid in shell)
            / os.sysconf("SC_CLK_TCK")
            / elapsed
            * 100,
            3,
        ),
        "shell_context_switches_per_s": round(
            sum(last[pid]["switches"] - first[pid]["switches"] for pid in shell) / elapsed, 2
        ),
        "python_workers": sum(proc["name"].startswith("python") for proc in last.values()),
        "sample_seconds": round(elapsed, 3),
    }


def run_once(profile=None, profile_features=PROFILE_FEATURES):
    with tempfile.TemporaryDirectory(prefix="zephyrus-performance-") as directory:
        temporary = Path(directory)
        data = temporary / "data"
        applications = data / "applications"
        applications.mkdir(parents=True)
        for index in range(300):
            (applications / f"fixture-{index}.desktop").write_text(desktop_entry(index))
        env = dict(os.environ)
        for key in (
            "HYPRLAND_INSTANCE_SIGNATURE",
            "WAYLAND_DISPLAY",
            "DISPLAY",
            "ALL_PROXY",
            "all_proxy",
            "NO_PROXY",
            "no_proxy",
        ):
            env.pop(key, None)
        env.update(
            {
                "XDG_CONFIG_HOME": str(temporary / "config"),
                "XDG_DATA_HOME": str(data),
                "XDG_DATA_DIRS": str(temporary / "empty"),
                "XDG_CONFIG_DIRS": str(temporary / "empty"),
                "XDG_CACHE_HOME": str(temporary / "cache"),
                "XDG_STATE_HOME": str(temporary / "state"),
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
                "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(temporary / "no-system-bus"),
                "https_proxy": "http://127.0.0.1:9",
                "http_proxy": "http://127.0.0.1:9",
            }
        )
        command = ["quickshell", "-p", str(ROOT / "performance.qml"), "--no-color"]
        profiler_command = None
        if profile:
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            command.extend(["--debug", str(port), "--waitfordebug"])
            profiler_command = [
                "qmlprofiler",
                "--attach",
                "127.0.0.1",
                "--port",
                str(port),
                "--include",
                profile_features,
                "-o",
                str(profile.resolve()),
            ]
        log = temporary / "run.log"
        samples = {phase: [] for phase in PHASES}
        started = time.monotonic()
        with log.open("w") as output:
            process = subprocess.Popen(
                ["dbus-run-session", "--", *command],
                cwd=ROOT,
                env=env,
                stdout=output,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            profiler = (
                subprocess.Popen(profiler_command, env=env, stdout=output, stderr=subprocess.STDOUT)
                if profiler_command
                else None
            )
            try:
                phase = ""
                while process.poll() is None:
                    content = log.read_text()
                    for line in content.splitlines():
                        if "PERF_PHASE " in line:
                            phase = line.split("PERF_PHASE ", 1)[1].strip()
                    if phase in samples:
                        samples[phase].append((time.monotonic(), processes(process.pid)))
                    if time.monotonic() - started > 60:
                        raise RuntimeError("Benchmark timed out\n" + content)
                    time.sleep(0.05)
            finally:
                # Also close private bus/helpers if a benchmark or profiler fails.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
                if profiler:
                    try:
                        profiler.wait(timeout=45)
                    except subprocess.TimeoutExpired:
                        profiler.terminate()
                        profiler.wait(timeout=5)
        content = log.read_text()
        if process.returncode or any(
            message in content
            for message in (
                "PERF_FAIL",
                "ReferenceError",
                "TypeError",
                "Binding loop",
                "Cannot assign",
                "ERROR qml:",
            )
        ):
            raise RuntimeError(content)
        result = next(
            (
                json.loads(line.split("PERF_RESULT ", 1)[1])
                for line in content.splitlines()
                if "PERF_RESULT " in line
            ),
            None,
        )
        if result is None:
            raise RuntimeError("No benchmark result\n" + content)
        if profile and (not profile.exists() or not profile.stat().st_size):
            raise RuntimeError("No QML trace captured\n" + content)
        if profile:
            with profile.open("rb") as trace:
                trace.seek(max(0, profile.stat().st_size - 512))
                if b"</trace>" not in trace.read() or (profiler and profiler.returncode):
                    raise RuntimeError("QML trace was not finalized\n" + content)
        result["resources"] = {phase: resource_summary(samples[phase]) for phase in PHASES}
        if result["resources"]["released"]["python_workers"]:
            raise RuntimeError("Applications left a worker running after Desktop")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument(
        "--profile", type=Path, help="Save a QML trace; never compare profiled timings"
    )
    parser.add_argument(
        "--profile-features",
        default=PROFILE_FEATURES,
        help="Comma-separated qmlprofiler features; add javascript for function traces",
    )
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    if args.baseline and args.baseline.resolve() == args.output.resolve():
        parser.error("--output must not overwrite --baseline")
    if args.profile:
        if args.profile.resolve() == args.output.resolve():
            parser.error("--profile and --output must be different files")
        args.profile.parent.mkdir(parents=True, exist_ok=True)
    runs = []
    for index in range(1 if args.profile else args.runs):
        runs.append(run_once(args.profile, args.profile_features))
        print(f"Completed run {index + 1}", flush=True)
    metrics = {
        key: statistics.median(run[key] for run in runs)
        for key in runs[0]
        if key not in ("resources", "apps_open_ms")
    }
    metrics["apps_open_ms"] = statistics.median(
        value for run in runs for value in run["apps_open_ms"]
    )
    metrics["apps_cold_open_ms"] = statistics.median(run["apps_open_ms"][0] for run in runs)
    metrics["apps_warm_open_ms"] = statistics.median(
        value for run in runs for value in run["apps_open_ms"][1:]
    )
    for phase in PHASES:
        for key in (
            "tree_rss_kib",
            "shell_cpu_pct",
            "shell_context_switches_per_s",
            "python_workers",
        ):
            metrics[phase + "_" + key] = statistics.median(
                run["resources"][phase][key] for run in runs
            )
    result = {
        "schema": 1,
        "profiled": bool(args.profile),
        "workload_sha256": workload_signature(),
        "sources": {
            str(path): hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in (
                "core/windows/WindowOrderModel.qml",
                "drawers/SpaceSearch.qml",
                "plugins/apps/Main.qml",
            )
        },
        "environment": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "quickshell": subprocess.check_output(["quickshell", "--version"], text=True).strip(),
            "renderer": "offscreen/software",
            "apps": 300,
        },
        "metrics": metrics,
        "runs": runs,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(metrics, indent=2))
    if args.baseline:
        baseline = json.loads(args.baseline.read_text())
        if (
            baseline["profiled"]
            or result["profiled"]
            or baseline["environment"] != result["environment"]
            or baseline.get("workload_sha256") != result["workload_sha256"]
        ):
            raise RuntimeError(
                "Compare only unprofiled runs with the same workload and environment"
            )
        print("Changes versus baseline (negative is better):")
        for key, value in metrics.items():
            before = baseline["metrics"].get(key)
            if before:
                print(f"{key}: {(value / before - 1) * 100:+.1f}% ({before:.3f} -> {value:.3f})")


if __name__ == "__main__":
    main()
