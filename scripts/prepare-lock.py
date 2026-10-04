#!/usr/bin/env python3
"""Synchronize the lock background before systemd starts the shell."""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.wallpaper import sync_lock_background

sync_lock_background(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")))
