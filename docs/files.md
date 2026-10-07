# Files

Files has **Local**, **Nextcloud**, and **Google Drive** tabs. Each remembers its
folder while Files is open. Local browsing stays inside your home directory.
Search filters the loaded entries; Google Drive's **Load more** fetches the next
page. Both cloud tabs support folders and the **New folder** action.

Click a file or choose **Open** to use your system's configured default app.
Nextcloud and ordinary Google Drive files open as local working copies; saving
in your app updates the original cloud file after writes settle. Opening the app
hides the Files overlay while its editing session keeps syncing. Google Docs,
Sheets, Slides, and other native Workspace items open in their browser editor.

Use **Copy to** or **Move to** in an entry's cog menu for transfers, including
uploads and downloads. The picker can browse any of the three providers, so cloud-to-cloud
copies also work. Folders are copied recursively, including hidden files and
empty folders. Existing destination items are preserved with numbered copy names;
folders are never merged. Moves copy everything first and only then send the
source to Trash after checking that the source has not changed. Nextcloud deletion
also uses the source ETag when available. A failed or cancelled transfer preserves its source. Files
already copied before a cancellation remain in the destination. Local symlink
folders are rejected to prevent loops; moving symlinks is unsupported. Folder
transfers are limited to 10,000 entries and 64 nesting levels.

Transfers use a bounded queue with two concurrent jobs. **Activity** opens a
floating popup with progress, throughput, time estimates, cancellation, and
recent results, and retry for failed/cancelled jobs. Unknown sizes use indeterminate progress rather than invented
time estimates. Finished and failed rows can be dismissed without removing files.
Plain status and error messages use desktop notifications and Attention. Files stays
alive while editing sessions, jobs, or custom actions are active, including after
selecting Desktop or another space, and releases its hidden instance when the
last job and editing session settle. Escape or explicit Close destroys the module and cancels its
owned work. Transfers are session jobs and are not restored after a shell restart.

**Activity** lists cloud editing sessions. Choose **Stop syncing** after finishing
in the editor; pending saves finish before the session ends. Files cannot infer
when every external editor closes a document, so sessions remain active until
you stop them. **Save As** to a different local filename creates an independent
file; only saves to the opened working copy sync back. Use **Copy to** to upload
that separate file.

Working copies and their revision records live under
`$XDG_DATA_HOME/zephyrus-shell/files/working-copies` (normally
`~/.local/share/zephyrus-shell/files/working-copies`). Copies are kept after
closing Files, failures, or conflicts. Reopen Files and choose **Resume syncing**
in Activity, or open the same cloud file again, to resume an interrupted session.
Restored sessions start paused. A changed cloud revision pauses save-back and
preserves both versions; **Open working copy** opens your local edits, and
**Pause syncing** releases the active session. Copy those edits to a new cloud
file to resolve a conflict; resuming never forces an overwrite. Changing accounts
cannot upload a previous account's working copies. Read-only Drive files open as
read-only local copies; **Copy to** can create a separate editable copy.

Save-back stages a stable snapshot and conditionally replaces the original using
its ETag. Nextcloud uses WebDAV `If-Match`; Drive uses its v2 file ETag and media
update endpoint, while browsing and transfers continue using v3. A missing
revision or receipt pauses editing rather than risking an unchecked overwrite.
Files needs local space for the working copy and one save snapshot. Completed
working copies remain available locally and can be removed when no longer needed.

Keyboard shortcuts: **Ctrl+R** refreshes, **Alt+Up** opens the parent folder,
**Ctrl+Shift+N** creates a folder. The existing list navigation and cog menu
keyboard controls continue to work.

## Cloud accounts

Nextcloud reuses the configured `dav` capability and private credential files
in [nextcloud.json](nextcloud.md). It uses the account's scoped Files WebDAV
endpoint; no credentials or provider logic live in QML. Transfer uploads use exclusive
creation so they cannot overwrite an existing server file.

Google Drive uses a Google **desktop/installed application** OAuth client. Save
its JSON outside the repository at
`$XDG_CONFIG_HOME/zephyrus-shell/credentials/google-drive/client.json`, or add a
`google_drive` object to `files.json` alongside `actions`:

```json
{
  "actions": [],
  "google_drive": {"client_secret_file": "/home/me/private/google-client.json"}
}
```

Select **Connect Google Drive** and complete sign-in in your system browser.
The Drive API must be enabled in that client's Google Cloud project; a project
in testing may require your account to be listed as a test user. Browsing and
moving existing files requires the `https://www.googleapis.com/auth/drive` scope;
Google's consent screen shows that access before you grant it. Sign-in uses
PKCE, a random state, and a temporary loopback callback. Refresh tokens are saved
atomically with mode `0600` under `credentials/google-drive/token.json`, never
sent to QML or committed. Reconnect if Google revokes or expires the grant.

Sign-in waits up to ten minutes and keeps Files alive while you use the browser.
**Continue Google sign-in** reopens the same attempt; cancel it in Activity to
start afresh. If consent finishes but the browser cannot reach the local callback,
choose **Finish sign-in** and paste the full address from that failed browser page
into Files. It must belong to the current attempt. The address is cleared after
submission and never included in notifications or stored. Expired attempts can
be restarted with **Connect Google Drive**.

Folder recovery offers **Connect Google Drive** when sign-in is required and
**Continue Google sign-in** while that attempt is active. Other folder errors
offer **Retry loading folder**. Failed or cancelled sign-in jobs have their own
**Retry** action in Activity, which starts or reopens sign-in.

Drive supports paginated My Drive folders, resumable chunk uploads, file
shortcuts, and browser links. Google Docs, Sheets, Slides, and Drawings download
as DOCX, XLSX, PPTX, and PDF respectively. Google's export limits and owner
restrictions still apply. Unsupported Google Workspace types can be opened in
the browser. Cross-cloud transfers stage one file at a time in a temporary local
folder and require space for that file; staging files are removed afterwards.

## Custom actions

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

Verification: `python3 -m unittest discover -s tests -p "test_file_open.py"`
and `bash scripts/check-file-open.sh` cover default-app opening, save-back,
conflicts, durable recovery, and editing retention. Transfer regressions use
`python3 -m unittest discover -s tests -p "test_file_transfers.py"`
and `bash scripts/check-transfers.sh`. Google sign-in regressions use
`python3 -m unittest discover -s tests -p "test_drive_sign_in.py"` and
`bash scripts/check-drive-sign-in.sh`. These smoke tests use real module entry
points and lifecycle actions with isolated state and stubbed remote endpoints.
