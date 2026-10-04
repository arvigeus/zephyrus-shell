pragma Singleton
import QtQuick

// Built-in spaces, in drawer order. No filesystem scan or startup process.
QtObject {
    readonly property var entries: [
        {
            "id": "apps",
            "name": "Applications",
            "icon": "layout-grid"
        },
        {
            "id": "files",
            "name": "Files",
            "icon": "folder"
        },
        {
            "id": "terminal",
            "name": "Terminal",
            "icon": "terminal"
        },
        {
            "id": "projects",
            "name": "Projects",
            "icon": "folder-git-2"
        },
        {
            "id": "movies",
            "name": "Movies",
            "icon": "film"
        },
        {
            "id": "series",
            "name": "TV Series",
            "icon": "tv"
        },
        {
            "id": "music",
            "name": "Music",
            "icon": "music"
        },
        {
            "id": "radio",
            "name": "Radio",
            "icon": "boom-box"
        },
        {
            "id": "pictures",
            "name": "Pictures",
            "icon": "image"
        },
        {
            "id": "games",
            "name": "Games",
            "icon": "gamepad-2"
        },
        {
            "id": "books",
            "name": "Books",
            "icon": "book-open"
        }
    ]
    function find(id) { return entries.find(entry => entry.id === id) || null; }
}
