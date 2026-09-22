import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../widgets"
import "../core"

ColumnLayout {
    id: root
    required property var inventory
    property bool input: false
    property bool expanded: false
    property bool identifiers: false
    readonly property var node: input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isStream && n.audio && !n.isSink)
    readonly property bool silenced: input ? sources.length > 0 && sources.every(n => n.audio.muted) : !!node && node.audio.muted
    readonly property var choices: Pipewire.nodes.values.filter(n => !n.isStream && n.audio && n.isSink !== input)
    Layout.fillWidth: true; spacing: 4
    RowLayout {
        Layout.fillWidth: true
        IconButton {
            iconName: root.input ? (root.silenced ? "mic-off" : "mic") : (root.silenced ? "volume-x" : "volume-2")
            text: root.input ? (root.silenced ? "Enable all microphones" : "Disable all microphones") : (root.silenced ? "Unmute speakers" : "Mute speakers")
            enabled: !!root.node
            onClicked: {
                const muted = !root.silenced;
                if (root.input) root.sources.forEach(n => n.audio.muted = muted);
                else root.node.audio.muted = muted;
            }
        }
        LevelSlider {
            Layout.fillWidth: true; from: 0; to: 1
            enabled: !!root.node && !!root.node.audio
            value: enabled ? root.node.audio.volume : 0
            onMoved: root.node.audio.volume = value
            Accessible.name: root.input ? "Microphone gain" : "Output volume"
        }
        Label { text: root.node ? Math.round(root.node.audio.volume * 100) + "%" : "—"; color: Theme.muted; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
        IconButton { iconName: root.expanded ? "chevron-up" : "chevron-down"; text: root.input ? "Choose microphone" : "Choose speakers"; onClicked: root.expanded = !root.expanded }
    }
    ColumnLayout {
        visible: root.expanded; Layout.fillWidth: true; Layout.leftMargin: 48
        Repeater {
            model: root.choices
            Action {
                required property var modelData
                Layout.fillWidth: true
                text: root.inventory.describe(modelData).label + (modelData === root.node ? " · Selected" : "")
                enabled: root.inventory.describe(modelData).available
                contentItem: RowLayout {
                    Icon { name: root.input ? "mic" : root.inventory.describe(modelData).role === "headphones" || root.inventory.describe(modelData).role === "headset" ? "headphones" : "volume-2" }
                    Label { text: root.inventory.describe(modelData).label; Layout.fillWidth: true; elide: Text.ElideRight }
                    Icon { name: "check"; visible: modelData === root.node }
                }
                onClicked: {
                    if (root.input) Pipewire.preferredDefaultAudioSource = modelData;
                    else Pipewire.preferredDefaultAudioSink = modelData;
                }
            }
        }
        Action { text: root.identifiers ? "Hide device identifiers" : "Device identifiers & naming"; Layout.fillWidth: true; onClicked: root.identifiers = !root.identifiers }
        Repeater { model: root.identifiers ? root.choices : []; Label { required property var modelData; text: root.inventory.describe(modelData).detail; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; font.pixelSize: 11 } }
        Repeater { model: root.identifiers ? root.inventory.snapshot.errors || [] : []; Label { required property string modelData; text: modelData; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap } }
        Action { visible: root.identifiers; text: "Reload names"; onClicked: root.inventory.refresh() }
        Label { visible: root.choices.length === 0; text: "No device available"; color: Theme.muted }
    }
}
