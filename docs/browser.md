# Browser command

Create `$XDG_CONFIG_HOME/zephyrus-shell/browser.json` to choose the command used
for web links. If `XDG_CONFIG_HOME` is unset, use `~/.config`.

```json
{
  "command": ["firefox", "--kiosk"],
  "modules": {
    "games": ["/home/me/bin/open-game-store"]
  }
}
```

The shell appends the URL as the final argument. A command can be an argument
array or a shell-style command string. It is run directly without a shell; use a
wrapper script if you need setup and cleanup around the browser. A module entry
overrides the shared command. With no entry, the desktop URL opener (`xdg-open`)
is used. Module code can also pass a command to `Browser.open(url, moduleId,
command)` for a session-specific override.
