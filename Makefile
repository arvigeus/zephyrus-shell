.PHONY: check lint test smoke native benchmark
.DEFAULT_GOAL := check

QMLTESTRUNNER ?= /usr/lib/qt6/bin/qmltestrunner
PERF_OUTPUT ?= tests/artifacts/performance-baseline.json
SMOKE := $(filter-out tests/smoke/lib.sh,$(wildcard tests/smoke/*.sh))

# Everything that runs without touching the current desktop.
check: lint test smoke

lint:
	ruff check .
	ruff format --check .
	ty check

test:
	python3 -m unittest discover -s tests -q
	QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software $(QMLTESTRUNNER) -input tests/qml -import .
	node --test tests/*.test.cjs
	python3 tests/perf/budgets.py

# Real entry points in private XDG directories and D-Bus sessions.
# Run one with: bash tests/smoke/<name>.sh
smoke:
	@set -e; for check in $(SMOKE); do echo "== $$check"; bash $$check; done

# Needs a running Wayland session; isolated compositors are started where possible.
native:
	Hyprland --verify-config -c "$(CURDIR)/hyprland/hyprland.lua"
	python3 tests/native/focus.py
	python3 tests/native/focus.py --window-controls
	bash tests/native/windows.sh
	bash tests/native/wayland.sh

benchmark:
	python3 tests/perf/benchmark.py --output "$(PERF_OUTPUT)"
