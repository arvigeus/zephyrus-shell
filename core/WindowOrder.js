.pragma library

// Keep Wayland handles (activation and icons) while ordering by compositor geometry.
function ordered(toplevels, clients) {
    const byWindow = new Map();
    for (const client of clients) {
        if (client.wayland && client.lastIpcObject && client.lastIpcObject.at && client.lastIpcObject.at.length >= 2)
            byWindow.set(client.wayland, client.lastIpcObject);
    }
    return Array.from(toplevels, (window, index) => ({window, index, info: byWindow.get(window)}))
        .sort((a, b) => {
            if (!a.info || !b.info) {
                if (!!a.info !== !!b.info) return a.info ? -1 : 1;
                return a.index - b.index;
            }
            const monitor = a.info.monitor - b.info.monitor;
            const workspace = a.info.workspace.id - b.info.workspace.id;
            if (monitor || workspace) return monitor || workspace;
            // Floating windows have no column order; retain their launch order after columns.
            if (!!a.info.floating !== !!b.info.floating) return a.info.floating ? 1 : -1;
            if (a.info.floating) return a.index - b.index;
            return a.info.at[0] - b.info.at[0] || a.info.at[1] - b.info.at[1] || a.index - b.index;
        })
        .map(entry => entry.window);
}
