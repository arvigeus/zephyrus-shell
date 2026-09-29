function summarize(output, home) {
    const base = home.replace(/\/+$/, "") || "/";
    const prefix = base === "/" ? "/" : base + "/";
    let total = 0;
    const sizes = [];
    for (const record of output.split("\u0000")) {
        const separator = record.indexOf("\t");
        if (separator < 1) continue;
        const bytes = Number(record.slice(0, separator));
        const path = record.slice(separator + 1).replace(/\/+$/, "") || "/";
        if (!Number.isFinite(bytes) || bytes < 0) continue;
        if (path === base) total = bytes;
        else if (path.startsWith(prefix)) {
            const name = path.slice(prefix.length);
            if (name && !name.includes("/")) sizes.push({name: name, bytes: bytes});
        }
    }
    if (!total) total = sizes.reduce((sum, item) => sum + item.bytes, 0);
    const threshold = Math.max(64 * 1048576, total * 0.01);
    sizes.sort((a, b) => b.bytes - a.bytes || a.name.localeCompare(b.name));
    const prominent = sizes.filter(item => item.bytes >= threshold);
    const other = Math.max(0, total - prominent.reduce((sum, item) => sum + item.bytes, 0));
    if (other) prominent.push({name: "Other folders & files", bytes: other});
    return {home: base, total: total, threshold: threshold, entries: prominent};
}
