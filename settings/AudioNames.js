function describe(node, snapshot) {
    if (!node) return {label: "No device available", detail: "", available: false};
    const route = snapshot.devices ? snapshot.devices[node.name] : null;
    const properties = Object.assign({}, node.properties || {}, route ? route.properties : {}, {"node.name": node.name});
    if (!properties["node.description"]) properties["node.description"] = node.description;
    const rule = (snapshot.rules || []).find(rule =>
        Object.keys(rule.match || {}).every(key => String(properties[key] || "") === rule.match[key]) &&
        Object.keys(rule.contains || {}).every(key => String(properties[key] || "").includes(rule.contains[key])));
    return {
        label: rule ? rule.label : node.description || node.name,
        role: rule && rule.role ? rule.role : (node.isSink ? "speaker" : "microphone"),
        detail: (route && route.port ? route.port + " · " : "") + node.name,
        available: !route || route.available
    };
}
