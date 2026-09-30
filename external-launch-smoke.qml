import QtQuick
import Quickshell
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1440; implicitHeight: 1000
        ModuleLoader { id: overlay; anchors.fill: parent }
        Timer {
            interval: 100; running: true; repeat: true
            property var cases: ["movie-web", "movie-direct", "trailer", "rating", "series-web", "subtitles", "failure", "hidden-owner"]
            property int index: 0
            property int phase: 0
            property int ticks: 0
            property var media
            function find(item, predicate) {
                if (!item) return null;
                if (predicate(item)) return item;
                for (const child of item.children || []) {
                    const found = find(child, predicate);
                    if (found) return found;
                }
                return null;
            }
            function require(value, message) {
                if (!value) { console.error("EXTERNAL FAIL", cases[index], message); Qt.quit(); throw new Error(message); }
            }
            function next() { index++; phase = 0; ticks = 0; }
            onTriggered: {
                require(++ticks < 100, "Timed out waiting for handoff");
                if (index === cases.length) {
                    console.log("EXTERNAL PASS: web and direct playback, trailers, ratings, episodes, subtitles, failures, owning host");
                    Qt.quit(); return;
                }
                const action = cases[index];
                if (phase === 0) {
                    const id = action === "series-web" || action === "subtitles" ? "series" : "movies";
                    if (!Plugins.find(id)) return;
                    ShellState.openPlugin(id); phase = 1;
                } else if (phase === 1) {
                    const loader = find(overlay.item, item => item.objectName === "moduleContent");
                    if (!loader || !loader.item || loader.item.loading || !loader.item.selected.id || loader.item.titleLoading) return;
                    media = loader.item;
                    Browser.open("", "movies", "", media.host);
                    External.launch([], media.host);
                    require(ShellState.panel === "module", "Empty target closed module");
                    if (action === "movie-web" || action === "movie-direct" || action === "failure") {
                        media.providerIndex = action === "movie-direct" ? 1 : action === "failure" ? 999 : 0;
                        media.play(null, true);
                    } else if (action === "trailer") {
                        const button = find(media, item => item.text === "Trailers" && item.triggered !== undefined);
                        require(!!button, "Trailer button missing"); button.triggered(0);
                    } else if (action === "rating") {
                        const button = find(media, item => String(item.text || "").startsWith("IMDb:") && item.clicked !== undefined);
                        require(!!button, "Rating button missing"); button.clicked();
                    } else if (action === "series-web") {
                        if (media.episodeLoading || !media.seasons.length) return;
                        media.play(null, true);
                        require(media.tab === "episodes" && ShellState.pluginId === "series", "Episode chooser closed module");
                        media.play({season: "1", number: 1}, true);
                    } else if (action === "subtitles") {
                        if (!media.localFiles.length) return;
                        media.subtitlePath = media.localFiles[0].path; media.tab = "subtitles";
                        phase = 2; return;
                    } else if (action === "hidden-owner") {
                        ShellState.requestKeepRunning("movies", true);
                        ShellState.openPlugin("series");
                        Browser.open("https://example.org/hidden-owner", "movies", "", media.host);
                        require(ShellState.pluginId === "series" && !ShellState.runningPluginIds.includes("movies"), "Handoff closed the foreground module instead of its owner");
                        ShellState.close(); next(); return;
                    }
                    phase = 3;
                } else if (phase === 2) {
                    const subtitles = find(media, item => item.objectName === "subtitleBrowser");
                    if (subtitles.loading || !subtitles.inventory.files.length) return;
                    subtitles.playWith(subtitles.inventory.files[0].path); phase = 3;
                } else if (phase === 3) {
                    if (action === "failure") {
                        if (media.playLoading) return;
                        require(!!media.detailError && ShellState.pluginId === "movies", "Resolution failure closed module or lost error");
                        ShellState.close();
                    }
                    if (overlay.item) return;
                    require(ShellState.panel === "" && !ShellState.runningPluginIds.length, "Handoff left an overlay or live module");
                    next();
                }
            }
        }
    }
}
