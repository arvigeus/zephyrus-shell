import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../widgets" as W

Rectangle {
    id: root
    signal closeRequested()
    property var entries: []
    property bool loading: true
    property bool changing: false
    property bool confirmClear: false
    property string errorText: ""
    property int generation: 0
    readonly property var filtered: entries.filter(entry => entry.preview.toLowerCase().includes(search.text.trim().toLowerCase()))
    color: Theme.background; radius: Theme.radius; border.color: Theme.border
    focus: true
    Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())
    Keys.onEscapePressed: closeRequested()
    function refresh() {
        const current = ++generation;
        loading = true; errorText = "";
        service.request("list", {}, (result, error) => {
            if (current !== generation) return;
            loading = false;
            if (error) { errorText = error; return; }
            entries = result.entries;
            history.currentIndex = filtered.length ? 0 : -1;
        });
    }
    function act(op, entry) {
        if (changing) return;
        changing = true; errorText = "";
        service.request(op, entry ? {entry_id: entry.id} : {}, (result, error) => {
            changing = false;
            if (error) { errorText = error; return; }
            if (op === "copy") { root.closeRequested(); }
            else { confirmClear = false; refresh(); }
        });
    }
    ClipboardService { id: service; onReady: root.refresh() }
    Timer { id: resetClear; interval: 5000; onTriggered: root.confirmClear = false }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 12
        RowLayout {
            Layout.fillWidth: true
            W.Label { text: "Clipboard"; font.family: Theme.font; font.pixelSize: Theme.sp(20); font.weight: Font.DemiBold; Layout.fillWidth: true }
            W.IconButton { iconName: "x"; text: "Close clipboard"; onClicked: root.closeRequested() }
        }
        RowLayout {
            Layout.fillWidth: true
            W.SearchField {
                id: search; objectName: "clipboardSearch"; Layout.fillWidth: true; placeholderText: "Search clipboard history"
                onTextChanged: history.currentIndex = root.filtered.length ? 0 : -1
                onAccepted: if (history.currentItem) root.act("copy", history.currentItem.modelData)
                Keys.onEscapePressed: root.closeRequested()
                Keys.onDownPressed: { history.forceActiveFocus(); if (root.filtered.length) history.currentIndex = 0; }
            }
            W.IconButton { iconName: "refresh-cw"; text: "Refresh"; enabled: !root.loading && !root.changing; onClicked: root.refresh() }
            W.IconButton {
                iconName: "trash-2"; text: root.confirmClear ? "Confirm clear" : "Clear history"
                highlighted: root.confirmClear
                enabled: !!root.entries.length && !root.changing
                onClicked: {
                    if (root.confirmClear) root.act("clear", null);
                    else { root.confirmClear = true; resetClear.restart(); }
                }
            }
        }
        W.Label { text: "Choose an item to copy, then paste into your app."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        W.Label { visible: !!root.errorText; text: root.errorText; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
        W.BusySpinner { running: root.loading || root.changing; visible: running; Layout.alignment: Qt.AlignHCenter }
        W.Label {
            visible: !root.loading && !root.errorText && !root.filtered.length
            text: search.text.trim() ? "No matching entries" : "Your clipboard history is empty"
            color: Theme.muted; Layout.fillWidth: true
        }
        ListView {
            id: history; objectName: "clipboardHistory"
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            model: root.filtered; spacing: 6
            W.WheelScroll { view: history }
            ScrollBar.vertical: ScrollBar {}
            Keys.onReturnPressed: if (currentItem) root.act("copy", currentItem.modelData)
            Keys.onDeletePressed: if (currentItem) root.act("delete", currentItem.modelData)
            delegate: RowLayout {
                required property var modelData
                required property int index
                width: history.width; spacing: 6
                W.Action {
                    id: entryButton
                    Layout.fillWidth: true; implicitHeight: 64
                    enabled: !root.changing
                    highlighted: history.currentIndex === index
                    iconName: modelData.binary ? "image" : "clipboard"
                    text: modelData.preview
                    Accessible.name: "Copy " + modelData.preview
                    onClicked: root.act("copy", modelData)
                    contentItem: RowLayout {
                        spacing: 12
                        W.Icon { name: entryButton.iconName; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                        W.Label {
                            text: entryButton.text; Layout.fillWidth: true
                            color: entryButton.highlighted ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                        }
                    }
                }
                W.IconButton {
                    iconName: "trash-2"; text: "Remove this entry"; enabled: !root.changing
                    onClicked: root.act("delete", modelData)
                }
            }
        }
    }
}
