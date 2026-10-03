import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    objectName: "session-actions"
    required property var machine
    function execute(name, delay) {
        if (name === "suspend") KeepAwake.setMode("off");
        machine.run(name, delay);
    }
    readonly property var delays: [
        {minutes: 15, label: "15 min"}, {minutes: 30, label: "30 min"},
        {minutes: 60, label: "1 hour"}, {minutes: 90, label: "90 min"},
        {minutes: 120, label: "2 hours"}, {minutes: 180, label: "3 hours"},
        {minutes: 240, label: "4 hours"}, {minutes: 300, label: "5 hours"}
    ]
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
                HoldAction {
                    objectName: "session-action-" + parent.modelData.id
                    anchors.centerIn: parent
                    holdDuration: 2000
                    iconName: parent.modelData.id !== "suspend" ? parent.modelData.icon : SessionLock.paused ? "lock-open" : KeepAwake.mode === "screen" ? "eye" : KeepAwake.mode === "sleep" ? "coffee" : "moon"
                    text: parent.modelData.label
                    highlighted: parent.modelData.id === "suspend" && (KeepAwake.mode !== "off" || SessionLock.paused)
                    enabled: !root.machine.busy && (parent.modelData.id !== "logout" || !!root.machine.snapshot.hyprland)
                    ToolTip.text: "Hold for 2 seconds to " + parent.modelData.label.toLowerCase() + (parent.modelData.id === "suspend" && SessionLock.paused ? ". Automatic locking is disabled for this session." : "")
                    onActivated: root.execute(parent.modelData.id)
                }
                IconButton {
                    id: sleepOptions
                    objectName: visible ? "session-sleep-options" : ""
                    visible: parent.modelData.id === "suspend"
                    x: parent.width / 2 + 23
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    iconName: "chevron-up"
                    iconSize: 14
                    text: "Sleep options"
                    highlighted: sleepMenu.visible
                    enabled: !root.machine.busy
                    onClicked: sleepMenu.visible ? sleepMenu.close() : sleepMenu.open()
                }
                Popup {
                    id: sleepMenu
                    parent: sleepOptions
                    popupType: Popup.Item
                    x: parent.width - width
                    y: -height - 8
                    width: 218
                    padding: 10
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Action {
                            visible: KeepAwake.mode !== "sleep"
                            Layout.fillWidth: true
                            iconName: "coffee"
                            text: "Stay awake"
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
                            objectName: sleepOptions.visible ? "session-lock-toggle" : ""
                            Layout.fillWidth: true
                            iconName: "lock-open"
                            text: SessionLock.paused ? "Restore locking" : "Disable locking"
                            textAlignment: Text.AlignLeft
                            highlighted: SessionLock.paused
                            enabled: SessionLock.loaded && SessionLock.available && !SessionLock.busy
                            ToolTip.text: SessionLock.available
                                ? "Disable automatic locking and idle sleep until you restore locking or log out. The screen can still blank; manual locking remains available."
                                : "Automatic locking controls require a Hyprland session."
                            onClicked: { SessionLock.setPaused(!SessionLock.paused); sleepMenu.close(); }
                        }
                        Action {
                            visible: KeepAwake.mode !== "off"
                            Layout.fillWidth: true
                            iconName: "moon"
                            text: "Allow automatic sleep"
                            textAlignment: Text.AlignLeft
                            onClicked: { KeepAwake.setMode("off"); sleepMenu.close(); }
                        }
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 42
            HoldAction {
                anchors.centerIn: parent
                objectName: "session-action-poweroff"
                holdDuration: 2000
                iconName: "power"
                text: "Power off"
                enabled: !root.machine.busy
                ToolTip.text: "Hold for 2 seconds to power off"
                onActivated: root.execute("poweroff")
            }
            IconButton {
                id: shutdownOptions
                x: parent.width / 2 + 23
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                iconName: "chevron-up"
                iconSize: 14
                text: "Shutdown options"
                highlighted: shutdownMenu.visible
                enabled: !root.machine.busy
                onClicked: shutdownMenu.visible ? shutdownMenu.close() : shutdownMenu.open()
            }
            Popup {
                id: shutdownMenu
                parent: shutdownOptions
                popupType: Popup.Item
                x: parent.width - width
                y: -height - 8
                width: 242
                padding: 10
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border }
                contentItem: ColumnLayout {
                    spacing: 6
                    Label { text: "Shut down in"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(12) }
                    GridLayout {
                        columns: 2
                        Layout.fillWidth: true
                        rowSpacing: 2
                        columnSpacing: 2
                        Repeater {
                            model: root.delays
                            HoldAction {
                                required property var modelData
                                holdDuration: 2000
                                showLabel: true
                                iconSize: 16
                                iconName: "power"
                                text: modelData.label
                                ToolTip.text: "Hold for 2 seconds to shut down in " + text
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 36
                                onActivated: {
                                    root.execute("schedule-poweroff", modelData.minutes);
                                    shutdownMenu.close();
                                }
                            }
                        }
                    }
                    Label {
                        visible: !!root.machine.snapshot.scheduledShutdown
                        text: root.machine.snapshot.scheduledShutdown || ""
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.sp(11)
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
    Label {
        visible: !!SessionLock.error
        text: SessionLock.error
        color: Theme.danger
        Layout.fillWidth: true
        wrapMode: Text.Wrap
    }
}
