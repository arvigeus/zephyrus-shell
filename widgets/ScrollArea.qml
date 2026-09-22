import QtQuick
import QtQuick.Controls

ScrollView {
    id: root
    WheelScroll { parent: root.contentItem; view: root.contentItem }
}
