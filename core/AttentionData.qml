pragma Singleton
import QtQuick

QtObject {
    property var forecast: null
    property var cloud: null
    property string cloudMonth: ""
    property string weatherError: ""
    property string cloudError: ""
    property double weatherCheckedAt: 0
    property double cloudCheckedAt: 0
}
