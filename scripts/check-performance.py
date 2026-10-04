#!/usr/bin/env python3
"""Offline performance budgets; providers are fixtures, launchers are never run."""

import json
import statistics
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from games.backend import GamesBackend
from services.cache import JsonCache


def measure(operation, count=5):
    samples = []
    for _ in range(count):
        start = time.perf_counter()
        operation()
        samples.append((time.perf_counter() - start) * 1000)
    return round(statistics.median(samples), 2)


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    config = root / "games.json"
    config.write_text(json.dumps({"igdb_client_id": "fixture", "igdb_client_secret": "fixture"}))
    backend = GamesBackend(config=config, data=root / "games")
    backend.libraries = Mock(
        side_effect=AssertionError("Catalogue must not wait for launcher discovery")
    )
    backend.catalogue.browse = Mock(
        return_value=[{"id": n + 1, "name": "Game " + str(n)} for n in range(50)]
    )
    timings = {
        "games_init_ms": measure(backend.init),
        "games_cold_page_ms": measure(lambda: backend.browse({"refresh": True})),
        "games_cached_page_ms": measure(lambda: backend.browse({})),
    }
    cache = JsonCache("fixture", root)
    fetch = Mock(return_value={"items": list(range(50))})
    cache.load("same-page", 900, fetch)
    timings["shared_cached_page_ms"] = measure(lambda: cache.load("same-page", 900, fetch), 20)
    assert fetch.call_count == 1, "Repeated cached pages made extra provider requests"
    assert timings["games_init_ms"] < 100, timings
    assert timings["games_cached_page_ms"] < 150, timings
    assert timings["games_cold_page_ms"] < 500, timings
    assert timings["shared_cached_page_ms"] < 30, timings
    print(json.dumps(timings, indent=2))
