//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Quickshell
import "core"
import "core/windows" as Windows
import "drawers" as Drawers
import "shell" as Shell

// Fixed workloads against production components. No application is launched.
ShellRoot {
    id: root
    property var metrics: ({})
    property var clients: []
    property int batch: 0
    property int sizeIndex: 0
    property double batchStart: 0
    property double elapsed: 0
    property double openedAt: 0
    property int cycle: 0
    property var openSamples: []
    readonly property var search: searchLoader.item
    property int queryIndex: 0
    property int searchSizeIndex: 0
    property double queryElapsed: 0
    function report(phase) { console.log("PERF_PHASE", phase); }
    function find(object, name) {
        if (object.objectName === name) return object;
        for (const child of object.children || []) {
            const found = find(child, name);
            if (found) return found;
        }
        return null;
    }
    function check(condition, message) {
        if (!condition) { console.error("PERF_FAIL", message); Qt.quit(); throw new Error(message); }
    }
    Component { id: clientFactory; QtObject { property var wayland; property var lastIpcObject } }
    Windows.WindowOrderModel { id: order }
    function geometry(index, offset) {
        return {at: [index * 500 - offset, 80], monitor: 0, workspace: {id: 1}, floating: false};
    }
    function setupOrder() {
        for (const client of clients) client.destroy();
        const size = [8, 32, 64][sizeIndex];
        const next = [];
        for (let i = 0; i < size; ++i)
            next.push(clientFactory.createObject(root, {wayland: {id: i}, lastIpcObject: geometry(i, 0)}));
        clients = next;
        order.toplevels = next.map(client => client.wayland);
        order.clients = next;
        batch = 0; elapsed = 0;
        Qt.callLater(updateOrder);
    }
    function updateOrder() {
        batchStart = Date.now();
        const current = clients;
        for (let i = 0; i < current.length; ++i) current[i].lastIpcObject = geometry(i, batch * 10);
        Qt.callLater(finishOrder);
    }
    function finishOrder() {
        // Includes deferred publication, not only the geometry setters.
        elapsed += Date.now() - batchStart;
        check(order.windows.length === clients.length, "lost window handles");
        for (let i = 0; i < clients.length; ++i)
            check(order.windows[i] === clients[i].wayland, "changed window order on scroll");
        if (++batch < 40) { Qt.callLater(updateOrder); return; }
        metrics["window_batch_" + clients.length + "_ms"] = elapsed / batch;
        if (++sizeIndex < 3) Qt.callLater(setupOrder);
        else Qt.callLater(runSearch);
    }
    function runSearch() {
        const size = [100, 500, 1000][searchSizeIndex];
        const entries = [];
        for (let i = 0; i < size; ++i) entries.push({name: "Fixture App " + i,
            genericName: i % 2 ? "Editor" : "Browser", keywords: ["Internet", "Graphics"], icon: ""});
        search.applications = entries;
        queryIndex = 0; queryElapsed = 0;
        searchTyping.start();
    }
    Timer {
        id: searchTyping; interval: 16; repeat: true
        onTriggered: {
            const size = [100, 500, 1000][root.searchSizeIndex];
            const queries = ["fixture", "editor", "fixture internet", "missing", "Fixture App 9", "graphics"];
            const index = root.queryIndex % 6;
            const start = Date.now();
            root.find(root.search, "spacesSearchField").text = queries[index];
            const count = root.search.matches.length;
            const duration = Date.now() - start;
            // One event per query lets Qt render and dispose obsolete delegates.
            if (root.queryIndex >= 6) root.queryElapsed += duration;
            root.check(count === (index === 3 ? 0 : index === 1 ? size / 2 : index === 4 ? ({100: 19, 500: 95, 1000: 271})[size] : size), "search results changed");
            if (++root.queryIndex < 126) return;
            stop();
            root.metrics["spaces_query_" + size + "_ms"] = root.queryElapsed / 120;
            if (++root.searchSizeIndex < 3) { root.runSearch(); return; }
            searchLoader.active = false;
            order.toplevels = []; order.clients = [];
            for (const client of root.clients) client.destroy();
            root.clients = [];
            root.report("desktop"); desktopSample.start();
        }
    }
    FloatingWindow {
        implicitWidth: 1280; implicitHeight: 800
        Loader { id: searchLoader; anchors.fill: parent; sourceComponent: Drawers.SpaceSearch { applications: []; spaces: [] } }
        Shell.ModuleLoader { id: modules; anchors.fill: parent; screenName: "*" }
    }
    Timer { interval: 300; running: true; onTriggered: root.setupOrder() }
    Timer { id: desktopSample; interval: 1800; onTriggered: root.openApps() }
    function openApps() {
        report("busy");
        openedAt = Date.now();
        ShellState.openPlugin("apps");
        ready.start();
    }
    Timer {
        id: ready; interval: 5; repeat: true
        property int attempts: 0
        onTriggered: {
            if (++attempts % 1000 === 0) console.log("PERF_WAIT", ShellState.runningPluginIds, !!modules.item,
                modules.item ? modules.item.currentModule : null);
            if (!modules.item || !modules.item.currentModule || !modules.item.currentModule.catalogReady
                    || !modules.item.currentModule.gpuChoicesReady) return;
            stop();
            const app = modules.item.currentModule;
            root.check(app.applications.length === 300, "desktop entry fixture count");
            root.openSamples.push(Date.now() - root.openedAt);
            if (root.cycle === 0) {
                root.queryIndex = 0; root.queryElapsed = 0; appTyping.start();
            } else root.closeApps();
        }
    }
    Timer {
        id: appTyping; interval: 16; repeat: true
        onTriggered: {
            const app = modules.item.currentModule;
            const queries = ["fixture", "editor", "missing", "app 9", "internet", ""];
            const index = root.queryIndex % 6;
            const start = Date.now();
            root.find(app, "appsSearchField").text = queries[index];
            const count = app.matches.length;
            const duration = Date.now() - start;
            if (root.queryIndex >= 6) root.queryElapsed += duration;
            root.check(count === [300, 150, 0, 11, 300, 300][index], "Applications results changed");
            if (++root.queryIndex < 126) return;
            stop();
            root.metrics.apps_query_300_ms = root.queryElapsed / 120;
            root.report("apps"); appsSample.start();
        }
    }
    Timer { id: appsSample; interval: 1800; onTriggered: root.closeApps() }
    function closeApps() { report("busy"); ShellState.showDesktop(); released.start(); }
    Timer {
        id: released; interval: 10; repeat: true
        onTriggered: {
            if (modules.item) return;
            stop();
            root.check(ShellState.runningPluginIds.length === 0, "idle module retained");
            if (++root.cycle < 5) { root.openApps(); return; }
            root.metrics.apps_open_ms = root.openSamples;
            root.report("released"); finish.start();
        }
    }
    Timer {
        id: finish; interval: 1800
        onTriggered: { console.log("PERF_RESULT", JSON.stringify(root.metrics)); Qt.quit(); }
    }
    Timer { interval: 45000; running: true; onTriggered: { console.error("PERF_FAIL timed out"); Qt.quit(); } }
}
