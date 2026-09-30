import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../core/theme"
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
    readonly property var hours: ready ? (shown.hours || []).slice(0, 6) : []
    readonly property bool hoursBeside: width >= 340
    readonly property string localDate: ready ? shown.local_date || String(shown.observed_at || "").slice(0, 10) : ""
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

    GridLayout {
        visible: root.ready
        Layout.fillWidth: true
        columns: root.hoursBeside ? 2 : 1
        columnSpacing: 14
        rowSpacing: 15
        ColumnLayout {
            objectName: "weatherCurrent"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Icon { name: root.current.icon || ""; Layout.preferredWidth: root.hoursBeside ? 38 : 56; Layout.preferredHeight: root.hoursBeside ? 38 : 56 }
                Label {
                    text: root.ready ? Math.round(root.current.temperature) + "°C" : ""
                    font.pixelSize: root.hoursBeside ? 42 : 48
                    font.weight: Font.Light
                }
            }
            Label {
                objectName: "weatherDescription"
                text: root.current.description || ""
                color: Theme.muted
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            ColumnLayout {
                objectName: "weatherMetrics"
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 5
                Repeater {
                    model: [
                        {icon: "droplet", label: "Humidity", value: Math.round(root.current.humidity) + "%"},
                        {icon: "thermometer", label: "Feels like", value: Math.round(root.current.feels_like) + "°C"},
                        {icon: "wind", label: "Wind", value: Number(root.current.wind).toFixed(1) + " km/h"}
                    ]
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        Icon { name: modelData.icon; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                        Label { text: modelData.label; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
                        Label { text: modelData.value; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                }
            }
        }
        ColumnLayout {
            objectName: "weatherHours"
            Layout.preferredWidth: root.hoursBeside ? 146 : -1
            Layout.fillWidth: !root.hoursBeside
            Layout.alignment: Qt.AlignTop
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                Label { text: root.forecast && root.forecast.stale ? "Saved hours" : "Next hours"; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
                Label { text: "Precip."; color: Theme.muted; font.pixelSize: 10 }
            }
            Repeater {
                model: root.hours
                RowLayout {
                    required property var modelData
                    objectName: "weatherHour"
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: modelData.time.slice(11, 16); font.pixelSize: 11; Layout.preferredWidth: 34 }
                    Icon {
                        name: modelData.icon
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        Controls.ToolTip.visible: hourHover.hovered
                        Controls.ToolTip.text: modelData.description
                        HoverHandler { id: hourHover }
                    }
                    Label { text: Math.round(modelData.temperature) + "°"; font.pixelSize: 12; Layout.fillWidth: true }
                    Label {
                        text: modelData.precipitation_probability === null || modelData.precipitation_probability === undefined
                            ? "—" : Math.round(modelData.precipitation_probability) + "%"
                        color: Theme.muted
                        font.pixelSize: 11
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
            Label {
                visible: root.hours.length === 0
                text: root.loading ? "Loading…" : "Hourly forecast unavailable"
                color: Theme.muted
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
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

    Rectangle { visible: root.ready; Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

    Label {
        visible: root.ready
        text: "7-day outlook"
        color: Theme.muted
        font.pixelSize: 11
        Layout.fillWidth: true
    }

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
                Accessible.name: modelData.description
                Layout.fillWidth: true
                Layout.preferredWidth: root.width / (root.width < 300 ? 4 : 7)
                spacing: 3
                Label {
                    text: modelData.date === root.localDate ? "Today" : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd")
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
                Icon {
                    name: modelData.icon
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 27; Layout.preferredHeight: 27
                    Controls.ToolTip.visible: dayHover.hovered
                    Controls.ToolTip.text: modelData.description
                    HoverHandler { id: dayHover }
                }
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
