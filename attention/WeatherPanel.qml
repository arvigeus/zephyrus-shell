import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"

ColumnLayout {
    id: root
    property bool narrow: false
    property var forecast: null
    property bool loading: false
    property string error: ""
    signal refreshRequested()
    readonly property var shown: forecast
    readonly property bool ready: shown !== null && shown !== undefined && shown.current !== undefined
    readonly property var current: ready ? shown.current : ({})
    readonly property var days: ready ? shown.days : []
    spacing: 15

    RowLayout {
        Layout.fillWidth: true
        Heading { text: "WEATHER"; Layout.fillWidth: true }
        IconButton {
            iconName: "refresh-cw"
            iconSize: 16
            text: "Refresh weather"
            enabled: !root.loading
            onClicked: root.refreshRequested()
        }
    }

    Label {
        visible: root.ready
        text: root.ready ? root.shown.location : ""
        Layout.fillWidth: true
        color: Theme.muted
        font.pixelSize: 12
    }

    RowLayout {
        visible: root.ready
        Layout.fillWidth: true
        spacing: 12
        Icon { name: root.ready ? root.current.icon || "" : ""; Layout.preferredWidth: 56; Layout.preferredHeight: 56 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { text: root.ready ? Math.round(root.current.temperature) + "°C" : ""; font.pixelSize: 48; font.weight: Font.Light }
            Label { text: root.ready ? root.current.description || "" : ""; color: Theme.muted }
        }
    }

    Label {
        visible: !root.ready
        text: root.loading ? "Loading weather…" : root.error || "Weather is not configured."
        Layout.fillWidth: true
        color: Theme.muted
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    GridLayout {
        visible: root.ready
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 8
        rowSpacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                spacing: 4
                Icon { name: "droplet"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Label { text: "Humidity"; color: Theme.muted; font.pixelSize: 11 }
            }
            Label { text: root.ready ? Math.round(root.current.humidity) + "%" : ""; font.weight: Font.DemiBold }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                spacing: 4
                Icon { name: "thermometer"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Label { text: "Feels like"; color: Theme.muted; font.pixelSize: 11 }
            }
            Label { text: root.ready ? Math.round(root.current.feels_like) + "°C" : ""; font.weight: Font.DemiBold }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                spacing: 4
                Icon { name: "wind"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Label { text: "Wind"; color: Theme.muted; font.pixelSize: 11 }
            }
            Label { text: root.ready ? Number(root.current.wind).toFixed(1) + " km/h" : ""; font.weight: Font.DemiBold }
        }
    }

    Rectangle { visible: root.ready; Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

    GridLayout {
        visible: root.ready
        Layout.fillWidth: true
        columns: root.width < 300 ? 4 : 7
        columnSpacing: 0
        rowSpacing: 10
        Repeater {
            model: root.days
            ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: root.width / (root.width < 300 ? 4 : 7)
                spacing: 3
                Label {
                    text: modelData.date === Qt.formatDate(new Date(), "yyyy-MM-dd") ? "Today" : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd")
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 11
                }
                Label {
                    text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "M/d")
                    color: Theme.muted
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 10
                }
                Icon { name: modelData.icon; Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 27; Layout.preferredHeight: 27 }
                Label { text: Math.round(modelData.high) + "°"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.weight: Font.DemiBold; font.pixelSize: 12 }
                Label { text: Math.round(modelData.low) + "°"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: Theme.muted; font.pixelSize: 11 }
            }
        }
    }

    Label {
        visible: root.ready
        text: root.forecast && root.forecast.stale ? "Saved forecast · Open-Meteo" : "Open-Meteo"
        Layout.fillWidth: true
        color: Theme.muted
        font.pixelSize: 11
    }
    Label {
        visible: root.ready && root.error !== ""
        text: root.error
        Layout.fillWidth: true
        color: Theme.muted
        font.pixelSize: 11
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
}
