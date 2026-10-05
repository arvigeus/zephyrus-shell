.PHONY: check lint test smoke

QMLTESTRUNNER ?= /usr/lib/qt6/bin/qmltestrunner

check: lint test smoke

lint:
	ruff check .
	ruff format --check .
	ty check

test:
	python3 -m unittest discover -s tests -q
	QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software $(QMLTESTRUNNER) -input tests/qml -import .
	node --test tests/*.test.cjs
	python3 scripts/check-performance.py

# Offscreen checks use real entry points with isolated state and private buses.
# Tests that operate the current desktop are explicit commands in README.md.
smoke:
	@set -e; for check in workers apps media books games modules retained settings warp theme spaces desktop language tray notifications session-lock terminal power; do bash scripts/check-$$check.sh; done
