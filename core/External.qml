pragma Singleton
import QtQuick
import Quickshell

QtObject {
    // User applications survive the module that handed off to them.
    function launch(command, host) {
        if (!command || !command.length) return;
        Quickshell.execDetached(command);
        if (host) host.hide();
    }
}
