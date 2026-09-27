#!/usr/bin/env python3
"""Launch a URL with the shared or module-specific browser command."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


def browser_argv(module, url, config_path=None, override=''):
    path = Path(config_path) if config_path else Path(os.environ.get(
        'XDG_CONFIG_HOME', Path.home() / '.config')) / 'zephyrus-shell/browser.json'
    try:
        config = json.loads(path.read_text())
    except FileNotFoundError:
        config = {}
    if not isinstance(config, dict):
        raise ValueError('browser.json must contain an object.')
    modules = config.get('modules') or {}
    if not isinstance(modules, dict):
        raise ValueError('browser.json modules must be an object.')
    command = override or modules.get(module) or config.get('command') or ['xdg-open']
    argv = shlex.split(command) if isinstance(command, str) else command
    if not isinstance(argv, list) or not argv or not all(isinstance(part, str) and part for part in argv):
        raise ValueError('Browser command must be a command string or a nonempty argument array.')
    return argv + [url]


def main():
    if len(sys.argv) not in (3, 4):
        raise SystemExit('Usage: open-browser.py MODULE URL [COMMAND]')
    argv = browser_argv(sys.argv[1], sys.argv[2], override=sys.argv[3] if len(sys.argv) == 4 else '')
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == '__main__':
    main()
