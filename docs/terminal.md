# Terminal

Each tab owns an independent native shell, current directory and scrollback. The
Plus button on the left adds a tab; its close button ends that session. Restart
replaces only the selected shell. Copy and Paste operate on the selected tab.

The terminal background, ordinary text, tabs and Commands menu follow the shared
appearance and update when switching between light and dark. ANSI output uses
QMLTermWidget's DarkPastels or BlackOnWhite scheme. Programs that explicitly
choose their own colors retain those colors.

Keyboard shortcuts while Terminal is visible:

- Ctrl+Shift+T: new tab.
- Ctrl+Shift+W: close selected tab.
- Ctrl+Tab / Ctrl+Shift+Tab: next / previous tab.
- Escape: close the entire module and its sessions.

Submitting input or running a saved command retains Terminal when selecting
Desktop or another module. Returning to Terminal restores all tabs. Closing or
restarting the last tab with submitted commands releases that retention. Explicit
module close always destroys the sessions. Retention follows submitted input,
not automatic foreground-job completion.

## Saved commands

The Play button on the right opens Commands. Define entries in
`$XDG_CONFIG_HOME/zephyrus-shell/terminal.json` (normally
`~/.config/zephyrus-shell/terminal.json`):

```json
{
  "commands": [
    {"name": "System information", "command": "uname -a"},
    {"name": "Disk usage", "command": "df -h"},
    {"name": "Shell project", "command": "cd ~/Projects/zephyrus-shell && git status --short"},
    {"name": "Pause idle locking (this session)", "command": "test -n \"$XDG_RUNTIME_DIR\" && test -n \"$HYPRLAND_INSTANCE_SIGNATURE\" && mkdir -p \"$XDG_RUNTIME_DIR/zephyrus-shell\" && touch \"$XDG_RUNTIME_DIR/zephyrus-shell/idle-lock-disabled-$HYPRLAND_INSTANCE_SIGNATURE\""},
    {"name": "Restore idle locking now", "command": "test -n \"$XDG_RUNTIME_DIR\" && test -n \"$HYPRLAND_INSTANCE_SIGNATURE\" && rm -f \"$XDG_RUNTIME_DIR/zephyrus-shell/idle-lock-disabled-$HYPRLAND_INSTANCE_SIGNATURE\""}
  ]
}
```

An empty configuration is created on first use. The menu includes an Open commands
configuration action and rereads the file every time it opens; no shell restart
is needed. Invalid JSON or entries display an error instead of stale commands.
See [the example](../config/terminal.example.json).

The example includes commands to pause only the five-minute idle lock and restore
it manually. While paused, the six-minute display blanking and idle suspend
listeners continue to run. The pause is scoped to the current Hyprland instance,
so logging out or restarting the compositor clears it. Manual locking and the
lock-before-suspend action remain available.

Selecting a name sends its command and Enter to the **selected tab's existing
shell**, using that tab's directory, environment and shell syntax. Commands never
run automatically. Run them at an idle prompt with no unfinished input. If a
program is running, wait for it to finish; if you have typed a draft command,
submit it or press Ctrl+U to clear it. Commands are shell code; quote paths and
arguments as you would at the prompt. Keep secrets out of the configuration.

## Verification

`python3 -m unittest discover -s tests -p test_terminal.py` validates configuration
handling. `bash scripts/check-terminal.sh` exercises real terminal sessions,
independent tabs, saved-command execution, menu reloads, theme changes, retention
and session destruction through the shared module host. It uses isolated XDG
configuration and a clean Bash environment.
