import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../core"
import "../widgets"

BarAction {
    id: root
    required property var barWindow
    readonly property alias menuWindow: menu
    property alias menuVisible: menu.visible
    property bool selectionOwner: false
    property bool restoringInputFocus: false
    readonly property bool loading: InputLanguage.selecting || restoringInputFocus
    Timer {
        id: releaseFocus
        interval: 100
        onTriggered: root.restoringInputFocus = false
    }
    Connections {
        target: InputLanguage
        function onSelectionFinished(code, success) {
            if (!root.selectionOwner) return;
            root.selectionOwner = false;
            if (code === "vi" && success && !InputLanguage.selectionPending) {
                // Cold-started IMEs need a fresh focus transition after they
                // attach to Hyprland. The closed menu must not own that focus.
                root.restoringInputFocus = true;
                releaseFocus.restart();
            }
        }
    }
    objectName: "languageButton"
    text: InputLanguage.description
    Accessible.name: "Input language: " + InputLanguage.languageName(InputLanguage.displayLanguage)
    highlighted: menu.visible
    contentItem: Item {
        implicitWidth: 24; implicitHeight: 24
        Icon { anchors.centerIn: parent; width: 20; height: 20; name: "globe"; visible: InputLanguage.displayLanguage === "en" }
        Label {
            objectName: "languageFlag"
            anchors.fill: parent
            visible: InputLanguage.displayLanguage !== "en"
            opacity: root.loading ? 0.45 : 1
            text: InputLanguage.flag; font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        BusySpinner {
            objectName: "languageLoading"
            anchors.centerIn: parent; width: 28; height: 28
            running: root.loading
            visible: running
        }
    }
    onClicked: {
        if (menu.visible) { menu.visible = false; return; }
        ShellState.dismissPanel();
        InputLanguage.refresh();
        const point = root.mapToItem(barWindow.contentItem, 0, root.height);
        menu.anchor.rect.x = Math.max(0, Math.min(barWindow.width - menu.width, point.x));
        menu.anchor.rect.y = point.y + 6;
        menu.visible = true;
    }
    Connections {
        target: ShellState
        function onPanelChanged() { menu.visible = false; }
    }
    PopupWindow {
        id: menu
        anchor.window: root.barWindow
        implicitWidth: 230; implicitHeight: choices.implicitHeight + 16
        color: "transparent"
        visible: false
        Shortcut { sequence: "Escape"; enabled: menu.visible; onActivated: menu.visible = false }
        onWindowConnected: Qt.callLater(() => { if (visible) grab.active = true; })
        onVisibleChanged: {
            if (!visible) grab.active = false;
            else Qt.callLater(() => { if (visible) grab.active = true; });
        }
        HyprlandFocusGrab {
            id: grab
            windows: [menu, root.barWindow]
            onCleared: menu.visible = false
        }
        Rectangle {
            objectName: "languageMenuPanel"
            anchors.fill: parent
            color: Theme.surface; radius: Theme.controlRadius; border.color: Theme.border
            ColumnLayout {
                id: choices
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                spacing: 2
                Repeater {
                    model: [{code: "en", flag: "", label: "English"}, {code: "bg", flag: "🇧🇬", label: "Български"}]
                        .concat(InputLanguage.available ? [{code: "vi", flag: "🇻🇳", label: "Tiếng Việt"}] : [])
                    Action {
                        required property var modelData
                        objectName: "language-" + modelData.code
                        text: modelData.label
                        toolTip: InputLanguage.languageName(modelData.code)
                        Accessible.name: toolTip + (modelData.code === InputLanguage.secondary ? " · Secondary language" : "")
                        highlighted: modelData.code === InputLanguage.language
                        enabled: !root.loading
                        Layout.fillWidth: true; implicitWidth: 200
                        contentItem: RowLayout {
                            spacing: 10
                            Item {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                Icon { objectName: "language-icon-" + modelData.code; anchors.centerIn: parent; width: 20; height: 20; name: "globe"; visible: modelData.code === "en" }
                                Label { anchors.fill: parent; visible: modelData.code !== "en"; text: modelData.flag; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            Label { text: modelData.label; Layout.fillWidth: true }
                            Icon {
                                objectName: "language-secondary-" + modelData.code
                                name: "check"
                                Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                visible: modelData.code === InputLanguage.secondary
                            }
                        }
                        onClicked: {
                            root.selectionOwner = modelData.code === "vi";
                            menu.visible = false;
                            InputLanguage.select(modelData.code);
                        }
                    }
                }
            }
        }
    }
}
