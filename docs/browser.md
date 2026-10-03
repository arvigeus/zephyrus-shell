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
wrapper script if you need setup and cleanup around the browser. Use absolute
paths for scripts; shell expansion such as `~`, `$HOME`, and `{{URL}}` is not
performed. A module entry overrides the shared command. Without a module
override, the shared command is used; without either, the desktop URL opener
(`xdg-open`) is used. To use the system browser for one module even when a shared
command is configured, set that module to `["xdg-open"]`. Module code can also
pass a command to `Browser.open(url, moduleId, command)` for a session-specific
override, which takes priority over the configuration. This configuration
affects shell web links; it does not change the system's default browser.

## Disposable Chromium window with ad blocking

The bundled `scripts/browser-chromium.sh` opens the URL in a fullscreen Chromium
app window with a fresh profile and the newest installed version of
[uBlock Origin Lite](https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh).
Install the extension in Chromium's Default profile first, then configure the
absolute path to the script in your checkout:

```json
{
  "command": ["/absolute/path/to/zephyrus-shell/scripts/browser-chromium.sh"],
  "modules": {
    "games": ["xdg-open"]
  }
}
```

Omit the `games` entry to use the launcher for that module too. The script takes
the URL as its single argument, creates a profile under
`$XDG_CACHE_HOME/zephyrus-shell/browser` (default `~/.cache`), and removes it after
Chromium exits. Each launch gets its own window and profile; cookies, logins,
history, and extension settings are not retained. Downloads saved outside the
profile remain. The extension uses its fresh-install filtering defaults.

The script finds the extension under
`$XDG_CONFIG_HOME/chromium/Default/Extensions/ddkjiahejlhfcafbddmgiahcphecmpfh`
(default `~/.config`). Set `ZEPHYRUS_ADBLOCK_DIR` to an unpacked extension
directory for another profile/location, or `ZEPHYRUS_CHROMIUM` to a different
Chromium executable. It fails if the browser or extension is missing.

Use Chromium: official Google Chrome builds have removed support for these
[extension-loading flags](https://groups.google.com/a/chromium.org/g/chromium-extensions/c/FxMU1TvxWWg).
