pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function open(url, moduleId, command) {
        const target = String(url || "");
        if (!target) return;
        const args = ["python3", Paths.file("scripts/open_browser.py"), moduleId || "", target];
        if (command) args.push(command);
        Quickshell.execDetached(args);
    }
}
