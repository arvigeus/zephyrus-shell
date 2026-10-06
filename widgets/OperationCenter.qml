import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "." as W

// Floats above the module; progress never participates in its layout.
Popup {
    id: root
    property var jobs: []
    property string message: ""
    property bool messageError: false
    readonly property int activeCount: jobs.filter(j => j.state === "running" || j.state === "queued").length
    property bool retryAvailable: false
    property string retryText: "Retry"
    signal retryRequested()
    signal actionRequested(var job)
    signal secondaryActionRequested(var job)
    signal cancelRequested(string jobId)
    width: Math.min(430, parent ? parent.width - 24 : 430)
    height: Math.min(implicitHeight, parent ? parent.height - 24 : 600)
    x: parent ? parent.width - width - 12 : 0
    y: parent ? parent.height - height - 12 : 0
    padding: 14
    margins: 12
    z: 100
    modal: false
    focus: false
    closePolicy: Popup.NoAutoClose
    popupType: Popup.Item

    function notify(text, error) {
        if (!text) return;
        message = text;
        messageError = !!error;
        if (parent && parent.visible) open();
        dismiss.restart();
    }
    function sizeLabel(value) {
        if (value >= 1073741824) return (value / 1073741824).toFixed(1) + " GB";
        if (value >= 1048576) return (value / 1048576).toFixed(1) + " MB";
        if (value >= 1024) return (value / 1024).toFixed(1) + " KB";
        return Math.floor(value || 0) + " B";
    }
    function remaining(job) {
        if (job.eta === null || job.eta === undefined || job.eta < 1) return "Estimating time…";
        const seconds = Math.ceil(job.eta);
        return seconds < 60 ? seconds + "s remaining" : Math.ceil(seconds / 60) + "m remaining";
    }
    onActiveCountChanged: { if (activeCount > 0) { dismiss.stop(); if (parent && parent.visible) open(); } else dismiss.restart(); }
    Connections { target: root.parent; function onVisibleChanged() { if (!root.parent.visible) root.close(); } }
    Timer { id: dismiss; interval: root.messageError ? 12000 : 7000; onTriggered: { if (!root.activeCount) root.close(); } }
    background: Rectangle { radius: Theme.controlRadius; color: Theme.surface; border.color: Theme.border }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            W.Icon { name: root.activeCount ? "download" : "bell"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
            W.Label { text: root.activeCount ? "Activity · " + root.activeCount + " active" : "Activity"; Layout.fillWidth: true; font.weight: Font.DemiBold }
            W.IconButton { iconName: "x"; text: "Hide activity"; implicitWidth: 30; implicitHeight: 30; onClicked: root.close() }
        }
        W.Label {
            Layout.fillWidth: true
            visible: !!root.message
            text: root.message
            wrapMode: Text.Wrap
            color: root.messageError ? Theme.danger : Theme.text
        }
        W.Action { objectName: "activityRetry"; visible: root.retryAvailable; text: root.retryText; onClicked: root.retryRequested() }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(360, jobColumn.implicitHeight)
            visible: root.jobs.length > 0
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                id: jobColumn
                width: parent.width
                spacing: 12
                Repeater {
                    model: root.jobs.slice().reverse().slice(0, 16)
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        readonly property bool active: ["queued", "running"].includes(modelData.state)
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            W.Label { Layout.fillWidth: true; text: row.modelData.title; elide: Text.ElideRight; font.weight: Font.Medium }
                            W.IconButton {
                                visible: row.active && row.modelData.cancellable !== false
                                enabled: !row.modelData.cancel_requested
                                iconName: "x"; text: "Cancel transfer"; implicitWidth: 28; implicitHeight: 28
                                onClicked: root.cancelRequested(row.modelData.job_id)
                            }
                        }
                        W.Label { Layout.fillWidth: true; text: row.modelData.error || row.modelData.detail || row.modelData.state; elide: Text.ElideMiddle; color: row.modelData.state === "failed" ? Theme.danger : Theme.muted }
                        W.Action { visible: !!row.modelData.actionLabel; text: row.modelData.actionLabel || ""; onClicked: root.actionRequested(row.modelData) }
                        W.Action { visible: !!row.modelData.secondaryActionLabel; text: row.modelData.secondaryActionLabel || ""; onClicked: root.secondaryActionRequested(row.modelData) }
                        ProgressBar {
                            visible: row.active && row.modelData.progressVisible !== false
                            Layout.fillWidth: true
                            indeterminate: !row.modelData.total
                            from: 0; to: Math.max(1, row.modelData.total || 0); value: row.modelData.done || 0
                        }
                        W.Label {
                            visible: row.active && (row.modelData.total > 0 || row.modelData.done > 0)
                            Layout.fillWidth: true
                            text: (row.modelData.unit === "tracks"
                                ? Number(row.modelData.done || 0).toFixed(1) + " / " + row.modelData.total + " tracks"
                                : root.sizeLabel(row.modelData.done) + (row.modelData.total ? " / " + root.sizeLabel(row.modelData.total) : " transferred")
                                    + (row.modelData.speed ? " · " + root.sizeLabel(row.modelData.speed) + "/s" : ""))
                                + (row.modelData.total ? " · " + root.remaining(row.modelData) : "")
                            color: Theme.muted
                            font.pixelSize: Theme.sp(11)
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
        W.Label { visible: !root.message && !root.jobs.length; text: "No recent activity"; color: Theme.muted }
    }
}
