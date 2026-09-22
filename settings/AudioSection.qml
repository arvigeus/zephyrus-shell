import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8
    property bool expanded: false
    AudioInventory { id: inventory }
    PwObjectTracker { objects: Pipewire.nodes.values.filter(node => !node.isStream && node.audio) }
    AudioDeviceControl { expanded: root.expanded; inventory: inventory }
    AudioDeviceControl { expanded: root.expanded; inventory: inventory; input: true }
    ColumnLayout {
        visible: !Pipewire.defaultAudioSource && (inventory.snapshot.inputProfiles || []).length > 0
        Layout.fillWidth: true
        Label { text: "Output-only audio mode is active."; color: Theme.muted; Layout.fillWidth: true }
        Repeater {
            model: inventory.snapshot.inputProfiles || []
            Action { required property var modelData; text: inventory.changingProfile ? "Enabling microphone…" : "Enable microphone alongside speakers"; enabled: !inventory.changingProfile; Layout.fillWidth: true; onClicked: inventory.enableInput(modelData) }
        }
    }
    Label { text: inventory.error; visible: text !== ""; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
