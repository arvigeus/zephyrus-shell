import QtQuick
import Quickshell.Services.UPower
import "../widgets"

Action {
    iconName: "settings"
    text: "Controls" + (UPower.displayDevice && UPower.displayDevice.isPresent ? "   ·   " + Math.round(UPower.displayDevice.percentage * 100) + "%" : "")
}
