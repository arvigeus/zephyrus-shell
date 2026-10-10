import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../core"
import "../widgets"
import "HomeUsage.js" as Usage

ScrollArea {
    id: root
    objectName: "hardware-details"
    required property var machine
    property string page: "cpu"
    readonly property var homeUsage: HardwareSnapshot.homeUsage || ({entries: [], total: 0})
    property string homeError: ""
    property string homeWarning: ""
    property string homeWarningDetails: ""
    readonly property bool homeReady: !!HardwareSnapshot.homeUsage
    readonly property string homePath: Quickshell.env("HOME")
    readonly property var hw: machine.snapshot.hardware || ({})
    contentWidth: availableWidth
    contentHeight: details.implicitHeight
    clip: true

    function formatSize(bytes) {
        let amount = Number(bytes) || 0;
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let unit = 0;
        while (amount >= 1024 && unit < units.length - 1) { amount /= 1024; unit++; }
        return (amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)) + " " + units[unit];
    }
    function refreshHome() {
        if (homeQuery.running) return;
        homeError = "";
        homeWarning = "";
        homeWarningDetails = "";
        homeQuery.running = true;
    }
    Component.onCompleted: if (page === "system") refreshHome()
    onPageChanged: if (page === "system" && !homeReady) refreshHome()
    Process {
        id: homeQuery
        command: ["du", "-x", "-B1", "-d", "1", "-0", "--", root.homePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = Usage.summarize(text, root.homePath);
                    if (result.total) HardwareSnapshot.homeUsage = result;
                    else root.homeError = "Could not read home storage usage.";
                } catch (error) { root.homeError = "Could not read home storage usage."; }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) {
                root.homeWarningDetails = text.trim().split("\n").slice(0, 3).join("\n");
                root.homeWarning = "Some paths were inaccessible or changed during the scan; sizes may be low.";
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) Qt.callLater(() => {
                if (!root.homeReady && !root.homeError) root.homeError = "Could not scan home directories.";
                else root.homeWarning = "Some paths were inaccessible or changed during the scan; sizes may be low.";
            });
        }
    }
    ColumnLayout {
        id: details
        width: root.availableWidth
        height: implicitHeight
        spacing: 14
        Heading { text: root.page === "system" ? "SYSTEM" : root.page.toUpperCase() }
        Label {
            visible: root.page !== "system"
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted
            text: root.page === "cpu" ? "Load average · " + (root.hw.load || "—") + "\nCPU boost · " + (root.hw.boost === "1" ? "Enabled" : root.hw.boost === "0" ? "Disabled" : "Unavailable")
                : "Applications choose a GPU through switcheroo-control. Use ROG Control Center for supported firmware GPU modes; changes may require a reboot."
        }
        Action {
            objectName: "cpu-boost-toggle"
            visible: root.page === "cpu"
            Layout.fillWidth: true
            iconName: "cpu"
            text: root.hw.boost === "1" ? "Disable CPU boost" : "Enable CPU boost"
            toolTip: "Higher CPU frequencies for this boot. Disable to reduce heat and power use."
            enabled: !root.machine.busy && ["0", "1"].includes(root.hw.boost) && root.hw.boostControlError === ""
            onClicked: root.machine.run("cpu-boost", root.hw.boost === "1" ? "off" : "on")
        }
        Label {
            visible: root.page === "cpu" && !!root.hw.boostControlError
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted
            text: root.hw.boostControlError || ""
        }
        Heading { text: "SENSORS"; visible: root.page !== "system" }
        Repeater {
            model: root.page === "system" ? [] : (root.hw.temperatures || []).filter(t => root.page === "gpu" ? /amdgpu|nouveau|nvidia/.test(t.driver) : /k10temp|coretemp|zenpower|acpitz/.test(t.driver))
            Label { required property var modelData; text: modelData.label + " · " + modelData.value + "°C"; color: Theme.muted }
        }
        Repeater { model: root.page === "cpu" ? root.hw.fans || [] : []; Label { required property var modelData; text: modelData.label + " · " + modelData.value + " RPM"; color: Theme.muted } }
        Action { visible: root.page !== "system"; text: "Refresh readings"; enabled: !root.machine.busy; onClicked: root.machine.refresh() }

        Label {
            visible: root.page === "system"
            text: "Memory · " + (root.hw.memoryUsed || 0) + " of " + (root.hw.memoryTotal || 0) + " GiB used\nSystem storage · " + (root.hw.storageUsed || 0) + " of " + (root.hw.storageTotal || 0) + " GiB used"
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted
        }
        Heading { text: "HOME DIRECTORIES"; visible: root.page === "system" }
        Label { visible: root.page === "system" && homeQuery.running; text: "Calculating home directory sizes…"; color: Theme.muted }
        Label { visible: root.page === "system" && root.homeReady; text: root.formatSize(root.homeUsage.total) + " in " + root.homeUsage.home; Layout.fillWidth: true; elide: Text.ElideMiddle; color: Theme.muted }
        Repeater {
            model: root.page === "system" && root.homeReady ? root.homeUsage.entries : []
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: modelData.name
                        Layout.fillWidth: true; elide: Text.ElideRight
                        HoverHandler { id: otherHover; enabled: modelData.name === "Other folders & files" }
                        ToolTip.visible: otherHover.hovered
                        ToolTip.text: "Folders under " + root.formatSize(root.homeUsage.threshold) + " (1% of home, minimum 64 MiB), plus files directly in home."
                    }
                    Label { text: root.formatSize(modelData.bytes); color: Theme.muted }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.raised
                    Rectangle {
                        width: parent.width * (root.homeUsage.total ? modelData.bytes / root.homeUsage.total : 0)
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }
                }
            }
        }
        Label {
            visible: root.page === "system" && root.homeWarning !== ""
            text: root.homeWarning
            color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap
            HoverHandler { id: warningHover; enabled: root.homeWarningDetails !== "" }
            ToolTip.visible: warningHover.hovered
            ToolTip.text: root.homeWarningDetails
        }
        Label { visible: root.page === "system" && root.homeError !== ""; text: root.homeError; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Action { visible: root.page === "system" && !homeQuery.running; text: "Refresh breakdown"; onClicked: root.refreshHome() }
    }
}
