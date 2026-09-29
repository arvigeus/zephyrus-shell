// BlueZ supplies freedesktop icon names; map device classes to bundled Lucide art.
function icon(type) {
    const name = (type || "").toLowerCase();
    if (name.includes("headset") || name.includes("headphone")) return "headphones";
    if (name.includes("speaker") || name.includes("audio")) return "speaker";
    if (name.includes("keyboard")) return "keyboard";
    if (name.includes("mouse") || name.includes("pointing")) return "mouse";
    if (name.includes("gamepad") || name.includes("controller")) return "gamepad-2";
    if (name.includes("phone")) return "smartphone";
    if (name.includes("tablet")) return "tablet";
    if (name.includes("watch")) return "watch";
    if (name.includes("computer") || name.includes("laptop")) return "laptop";
    if (name.includes("display") || name.includes("video")) return "monitor";
    return "bluetooth";
}
