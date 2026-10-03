# Files

The cog menu on each entry includes matching custom actions after the built-in
actions. Custom actions are flat menu items and run in the background. Files
stays alive while an action runs, including when you select Desktop or another
module. Explicitly closing Files ends its active custom actions.

Define them in `$XDG_CONFIG_HOME/zephyrus-shell/files.json` (normally
`~/.config/zephyrus-shell/files.json`). The Files module creates an empty
`{"actions": []}` file the first time it checks for custom actions. A match has
one of three kinds:

- `{"kind": "file", "value": "/home/me/path/to/file.ext"}` matches that exact
  file. Path values may also be relative to your home folder.
- `{"kind": "extension", "value": ".mka"}` matches files with that extension,
  ignoring case.
- `{"kind": "directory", "value": "/home/me/path/to/folder"}` matches that
  exact directory when it is selected. Relative paths are resolved from home.

Each action has a `name`, a `match`, and a shell `command`. Commands run through
`/bin/sh` with the selected entry's folder as their working directory. Use these
placeholders to refer to the selected entry; each substituted value is quoted
for the shell, so leave the placeholder itself unquoted:

- `{path}`: selected file or directory path.
- `{name}`: selected entry's name.
- `{directory}`: the containing folder for a file, or the selected folder for a
  directory.
- `{stem}` and `{extension}`: the selected entry's filename stem and suffix.

For example, this extracts the first audio stream from an `.mka` file to a
320 kbps AAC `.m4a` with the same filename stem. `-n` keeps ffmpeg from replacing
an existing output file. It requires `ffmpeg` on `PATH`:

```json
{
  "actions": [
    {
      "name": "Convert to M4A (320 kbps)",
      "match": {"kind": "extension", "value": ".mka"},
      "command": "ffmpeg -hide_banner -i {path} -map 0:a:0 -map_metadata 0 -vn -c:a aac -b:a 320k -movflags +faststart -n {directory}/{stem}.m4a"
    }
  ]
}
```

See [the example configuration](../config/files.example.json). Changes are read
when a cog menu opens; no shell restart is needed. Commands are shell code, so
only add commands you trust.
