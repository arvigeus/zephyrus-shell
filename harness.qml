//@ pragma UseQApplication
// Test entry point: runs the harness named by $ZEPHYRUS_HARNESS, e.g.
// ZEPHYRUS_HARNESS=tests/smoke/apps.qml quickshell -p harness.qml
// Quickshell only serves QML from directories its import scanner reaches from
// the entry file, so every directory a harness may use is imported here.
import Quickshell
import "attention" as Attention
import "clipboard" as Clipboard
import "core" as Core
import "core/theme" as CoreTheme
import "core/windows" as CoreWindows
import "drawers" as Drawers
import "modules/apps" as Apps
import "modules/books" as Books
import "modules/files" as Files
import "modules/games" as Games
import "modules/media" as Media
import "modules/movies" as Movies
import "modules/music" as Music
import "modules/pictures" as Pictures
import "modules/projects" as Projects
import "modules/radio" as Radio
import "modules/series" as Series
import "modules/terminal" as Terminal
import "services" as Services
import "settings" as Settings
import "shell" as Shell
import "widgets" as Widgets

ShellRoot {
    LazyLoader {
        active: true
        source: Qt.resolvedUrl(Quickshell.env("ZEPHYRUS_HARNESS"))
    }
}
