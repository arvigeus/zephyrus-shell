# Projects

The Projects space scans immediate, visible directories in `XDG_PROJECTS_DIR`.
It reads `XDG_PROJECTS_DIR` from the environment or `user-dirs.dirs`, then uses
`~/Projects` as the default. Existing folders appear without registration.
Symlinked and hidden entries are skipped.

Cards show a small project favicon or logo when available. Technologies are
detected from root-level manifests and markers when a folder first appears, then
saved in `$XDG_DATA_HOME/zephyrus-shell/project-profiles.json` (normally under
`~/.local/share`). Normal module loads reuse those saved badges. The per-project
Refresh action detects that project's technologies again; the top Refresh
button rescans all projects. Successful or failed starter setup also refreshes
the newly created project's profile after the terminal command ends. Replacing
a folder at the same path triggers a new detection. Badge SVGs come from the
pinned, locally bundled [Devicon set](../assets/devicon/README.md). The module
does not run project code while detecting technologies.

Selecting a project starts `zed <project directory>` (or `zeditor` when that is
the installed command). Successful launches are
recorded in `$XDG_DATA_HOME/zephyrus-shell/projects.json`; cards sort by that
time, with unopened projects sorted by name. When a Syntaxis workspace registry
exists, its last-opened times are also read for matching folders. Other Zed
launches do not update this history.

**New Project** offers the same 30 starter choices as Syntaxis, grouped into
Basics, Web, Backend, and Native. It creates one direct child of Projects, then
runs the chosen scaffolder in an embedded interactive terminal. Starters use
`mise x` to provide their toolchain and `mise use` to record it in the project.
The Empty starter needs no Mise. Vite+ needs an installed `vp` command. Closing
the setup dialog stops its terminal; the folder remains available for repair
or another attempt. Scaffolders can download packages from their own sources.

**Git Clone** accepts an HTTPS, SSH, or Git repository URL. It supports Full,
Blobless, and Shallow clone modes, reports Git progress, and lets you cancel.
The clone is staged within Projects and appears only after Git finishes; a
failed or cancelled clone removes its staging folder.

Each card has a menu for **Bootstrap**, **Update tools**, **Notes**, **Refresh**,
**Cleanup files**, and **Delete**. Bootstrap trusts and installs an existing
Mise configuration, or offers inferred tools from project manifests and writes
a local Mise configuration. Update tools runs a local Mise upgrade. Notes are
private to Zephyrus Shell in XDG application data. Cleanup previews Git ignored
files before removal and excludes common local configuration, such as `.env`
and `.direnv`. Delete requires the project's name and moves its folder to the
system Trash.

The **Recent Projects** menu provides **Update installed tools**, **Prune unused
tools**, and **Free up space**. Update and Prune use Mise and are disabled when
`mise` is unavailable. Free up space offers development package/build caches,
all installed Mise tool versions, and Bun/Deno/Rustup installations. Removing
installed tools requires typing `REMOVE TOOLS`. Cache cleanup targets known
development cache directories, including those under `XDG_CACHE_HOME`; it does
not clear the shell's general cache. All per-project options act only on direct
child folders of the XDG Projects directory.
