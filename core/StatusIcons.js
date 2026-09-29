function wifiIcon(strength, secured) {
    const base = secured ? "wireless-lock" : "wifi";
    const signal = Number(strength) || 0;
    return base + (signal < 0.4 ? "-low" : signal < 0.75 ? "-high" : "");
}

function volumeIcon(level, muted) {
    if (muted) return "volume-x";
    if (Number(level) <= 0) return "volume";
    return Number(level) < 0.5 ? "volume-1" : "volume-2";
}

function brightnessIcon(percent) {
    return Number(percent) < 34 ? "sun-dim" : Number(percent) < 67 ? "sun-medium" : "sun";
}

function batteryIcon(percent, charging) {
    if (charging) return "battery-charging";
    const level = Number(percent) || 0;
    return level <= 5 ? "battery" : level < 30 ? "battery-low" : level < 70 ? "battery-medium" : "battery-full";
}

function profileIcon(mode) {
    return ({"power-saver": "leaf", "balanced": "scale", "performance": "rocket"})[mode] || "cpu";
}

function gpuIcon(mode) {
    return ({"integrated": "square-dot", "hybrid": "squares-exclude", "smart": "square-sparkles"})[mode] || "gpu";
}
