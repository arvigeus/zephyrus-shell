"""Validate resource accounting independently of the measured workload."""

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "benchmark_shell", Path(__file__).resolve().parent / "perf/benchmark.py"
)
assert SPEC and SPEC.loader
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


def snapshot(ticks, switches, worker=True):
    result = {
        10: {"name": "quickshell", "rss_kib": 1000, "cpu_ticks": ticks, "switches": switches},
        11: {"name": "dbus-daemon", "rss_kib": 200, "cpu_ticks": 0, "switches": 0},
    }
    if worker:
        result[12] = {"name": "python3", "rss_kib": 300, "cpu_ticks": 0, "switches": 0}
    return result


class PerformanceTests(unittest.TestCase):
    def test_settled_resources_exclude_startup_and_exit_races(self):
        samples = [
            (0, snapshot(0, 0)),
            (0.4, snapshot(40, 100)),
            (1.4, snapshot(50, 120)),
            (1.5, {}),  # Quickshell exited while /proc was being sampled.
        ]
        with patch.object(benchmark.os, "sysconf", return_value=100):
            result = benchmark.resource_summary(samples)
        self.assertEqual(result["tree_rss_kib"], 1500)
        self.assertEqual(result["shell_cpu_pct"], 10)
        self.assertEqual(result["shell_context_switches_per_s"], 20)
        self.assertEqual(result["python_workers"], 1)

    def test_release_reports_no_worker_and_short_phases_are_rejected(self):
        result = benchmark.resource_summary(
            [(0, snapshot(0, 0, False)), (0.4, snapshot(0, 0, False)), (1.4, snapshot(0, 0, False))]
        )
        self.assertEqual(result["python_workers"], 0)
        with self.assertRaises(RuntimeError):
            benchmark.resource_summary([(0, snapshot(0, 0))])
