import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../widgets"

BarAction {
    id: root
    showToolTip: false
    readonly property var weather: AttentionData.forecast ? AttentionData.forecast.current : null
    text: Qt.formatDateTime(clock.date, "ddd, MMM d   ·   HH:mm") + (Attention.count ? "   · " + Attention.count : "")
    Accessible.description: weather ? weather.description + ", " + Math.round(weather.temperature) + " degrees Celsius" : ""
    contentItem: RowLayout {
        spacing: 8
        Label { text: root.text }
        Icon { visible: !!root.weather; name: root.weather ? root.weather.icon : "cloud"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
        Label { visible: !!root.weather; text: root.weather ? Math.round(root.weather.temperature) + "°C" : "" }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
