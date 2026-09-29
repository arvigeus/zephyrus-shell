import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    required property var machine
    property string pending: ""
    property int pendingDelay: 0
    readonly property var delays: [
        {minutes: 15, label: "15 min"}, {minutes: 30, label: "30 min"},
        {minutes: 60, label: "1 hour"}, {minutes: 90, label: "90 min"},
        {minutes: 120, label: "2 hours"}, {minutes: 180, label: "3 hours"},
        {minutes: 240, label: "4 hours"}, {minutes: 300, label: "5 hours"}
    ]
    function delayLabel(minutes) {
        const choice = delays.find(item => item.minutes === minutes);
        return choice ? choice.label : "";
    }
    Layout.fillWidth: true
    RowLayout {
        Layout.fillWidth: true
        Repeater {
            model: [{id: "logout", label: "Log out", icon: "log-out"}, {id: "suspend", label: "Sleep", icon: "moon"}, {id: "reboot", label: "Restart", icon: "rotate-ccw"}]
            Item {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 42
                IconButton {
                    anchors.centerIn: parent
                    iconName: parent.modelData.id !== "suspend" ? parent.modelData.icon : KeepAwake.mode === "screen" ? "eye" : KeepAwake.mode === "sleep" ? "coffee" : "moon"
                    text: parent.modelData.id !== "suspend" ? parent.modelData.label : KeepAwake.mode === "screen" ? "Allow screen blanking and sleep" : KeepAwake.mode === "sleep" ? "Enable automatic sleep" : "Sleep"
                    highlighted: parent.modelData.id === "suspend" && KeepAwake.mode !== "off"
                    enabled: !root.machine.busy && (parent.modelData.id !== "logout" || !!root.machine.snapshot.hyprland)
                    onClicked: {
                        if (parent.modelData.id === "suspend" && KeepAwake.mode !== "off") KeepAwake.setMode("off");
                        else root.pending = parent.modelData.id;
                    }
                }
                IconButton {
                    visible: parent.modelData.id === "suspend"
                    x: parent.width / 2 + 23
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    iconName: "chevron-up"
                    iconSize: 14
                    text: "Sleep options"
                    highlighted: sleepMenu.visible
                    enabled: !root.machine.busy
                    onClicked: sleepMenu.open()
                }
                Popup {
                    id: sleepMenu
                    x: parent.width - width
                    y: -height - 8
                    width: 218
                    padding: 10
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Action {
                            visible: KeepAwake.mode !== "sleep"
                            Layout.fillWidth: true
                            iconName: "coffee"
                            text: "Keep awake"
                            textAlignment: Text.AlignLeft
                            ToolTip.text: "Prevent automatic sleep while allowing the screen to dim or blank."
                            onClicked: { KeepAwake.setMode("sleep"); sleepMenu.close(); }
                        }
                        Action {
                            visible: KeepAwake.mode !== "screen"
                            Layout.fillWidth: true
                            iconName: "eye"
                            text: "Keep screen on"
                            textAlignment: Text.AlignLeft
                            ToolTip.text: "Prevent sleep, screen dimming, and screen blanking."
                            onClicked: { KeepAwake.setMode("screen"); sleepMenu.close(); }
                        }
                        Action {
                            visible: KeepAwake.mode !== "off"
                            Layout.fillWidth: true
                            iconName: "moon"
                            text: "Sleep"
                            textAlignment: Text.AlignLeft
                            ToolTip.text: "Put the device to sleep after confirmation."
                            onClicked: { root.pending = "suspend"; sleepMenu.close(); }
                        }
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 42
            IconButton {
                anchors.centerIn: parent
                iconName: "power"
                text: "Power off"
                enabled: !root.machine.busy
                onClicked: { root.pending = "poweroff"; root.pendingDelay = 0; }
            }
            IconButton {
                x: parent.width / 2 + 23
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                iconName: "chevron-up"
                iconSize: 14
                text: "Shutdown options"
                highlighted: shutdownMenu.visible
                enabled: !root.machine.busy
                onClicked: shutdownMenu.open()
            }
            Popup {
                id: shutdownMenu
                x: parent.width - width
                y: -height - 8
                width: 242
                padding: 10
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border }
                contentItem: ColumnLayout {
                    spacing: 6
                    Label { text: "Shut down in"; color: Theme.muted; font.pixelSize: 12 }
                    GridLayout {
                        columns: 2
                        Layout.fillWidth: true
                        rowSpacing: 2
                        columnSpacing: 2
                        Repeater {
                            model: root.delays
                            Action {
                                required property var modelData
                                text: modelData.label
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 36
                                onClicked: {
                                    root.pending = "schedule-poweroff";
                                    root.pendingDelay = modelData.minutes;
                                    shutdownMenu.close();
                                }
                            }
                        }
                    }
                    Label {
                        visible: !!root.machine.snapshot.scheduledShutdown
                        text: root.machine.snapshot.scheduledShutdown || ""
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 11
                    }
                    Action {
                        visible: !!root.machine.snapshot.scheduledShutdown
                        text: "Cancel scheduled shutdown"
                        Layout.fillWidth: true
                        onClicked: { shutdownMenu.close(); root.machine.run("cancel-poweroff"); }
                    }
                }
            }
        }
    }
    RowLayout {
        visible: root.pending !== ""
        Layout.fillWidth: true
        Action {
            text: root.pending === "schedule-poweroff" ? "Confirm shutdown in " + root.delayLabel(root.pendingDelay) : "Confirm " + root.pending
            destructive: true
            Layout.fillWidth: true
            enabled: !root.machine.busy
            onClicked: {
                if (root.pending === "suspend") KeepAwake.setMode("off");
                root.machine.run(root.pending, root.pending === "schedule-poweroff" ? root.pendingDelay : undefined);
                root.pending = "";
                root.pendingDelay = 0;
            }
        }
        Action { text: "Cancel"; onClicked: { root.pending = ""; root.pendingDelay = 0; } }
    }
}
