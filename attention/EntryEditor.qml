import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "../widgets"
import "../core"

Item {
    id: root
    property bool opened: false
    property bool busy: false
    property string error: ""
    property string kind: "VTODO"
    property var entry: null
    property var options: []
    property string collection: ""
    property bool allDay: true
    readonly property bool editing: entry !== null
    readonly property bool editable: !editing || !!entry.editable
    signal saveRequested(string kind, var entry)
    visible: opened

    function begin(itemKind, source, day, collections) {
        kind = itemKind;
        entry = source || null;
        const slug = source ? (itemKind === "VTODO" ? source.list_slug : source.calendar_slug) : "";
        options = source ? collections.filter(candidate => candidate.slug === slug)
                         : collections.filter(candidate => candidate.writable
                             && candidate.components.includes(itemKind)
                             && (itemKind === "VTODO" ? candidate.tasks_enabled : candidate.events_enabled));
        const preferred = itemKind === "VTODO" ? "Tasks" : "Personal";
        const chosen = source ? options[0] : options.find(candidate => candidate.name === preferred) || options[0];
        collection = chosen ? chosen.slug : "";
        collectionChoice.currentIndex = Math.max(0, options.findIndex(candidate => candidate.slug === collection));
        titleField.text = source ? source.summary : "";
        notesField.text = source ? source.description || "" : "";
        dueField.text = source && source.due ? source.due : "";
        allDay = source ? !!source.all_day : true;
        modeChoice.currentIndex = allDay ? 0 : 1;
        startDateField.text = itemKind === "VEVENT" ? (source ? source.date : day) : "";
        endDateField.text = itemKind === "VEVENT" ? (source
            ? (source.all_day ? source.last_date : Qt.formatDate(new Date(source.end), "yyyy-MM-dd")) : day) : "";
        startTimeField.text = itemKind === "VEVENT" && source && !source.all_day
            ? Qt.formatTime(new Date(source.start), "HH:mm") : "09:00";
        endTimeField.text = itemKind === "VEVENT" && source && !source.all_day
            ? Qt.formatTime(new Date(source.end), "HH:mm") : "10:00";
        error = "";
        busy = false;
        opened = true;
        Qt.callLater(() => titleField.forceActiveFocus());
    }
    function close() {
        if (!busy) opened = false;
    }
    function submit() {
        const payload = {
            collection: collection,
            href: entry ? entry.href : "",
            etag: entry ? entry.etag : "",
            summary: titleField.text,
            description: notesField.text
        };
        if (kind === "VTODO") payload.due = dueField.text.trim();
        else {
            payload.start_date = startDateField.text.trim();
            payload.end_date = endDateField.text.trim();
            payload.all_day = allDay;
            payload.start_time = startTimeField.text.trim();
            payload.end_time = endTimeField.text.trim();
        }
        error = "";
        saveRequested(kind, payload);
    }

    Rectangle {
        anchors.fill: parent
        color: "#b8000000"
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }
    Rectangle {
        width: Math.min(520, root.width - 40)
        height: Math.min(root.height - 24, root.kind === "VTODO" ? 500 : 570)
        anchors.centerIn: parent
        radius: Theme.controlRadius
        color: Theme.background
        border.color: Theme.border
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Label {
                text: (root.editing ? "Edit " : "New ") + (root.kind === "VTODO" ? "task" : "event")
                font.pixelSize: 20
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Label {
                visible: root.editing && !root.editable
                text: "This item is read only. Edit recurring items and read only calendars in Nextcloud."
                color: Theme.muted
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            Flickable {
                id: formScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: form.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                ColumnLayout {
                    id: form
                    width: formScroll.width - 8
                    spacing: 8
                    Label { text: "Title"; color: Theme.muted; font.pixelSize: 12 }
                    SearchField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: root.kind === "VTODO" ? "Task name" : "Event name"
                        enabled: root.editable && !root.busy
                        onAccepted: root.submit()
                    }
                    Label { text: root.kind === "VTODO" ? "Task list" : "Calendar"; color: Theme.muted; font.pixelSize: 12; Layout.topMargin: 8 }
                    Choice {
                        id: collectionChoice
                        Layout.fillWidth: true
                        model: root.options
                        textRole: "name"
                        enabled: !root.editing && !root.busy && root.options.length > 0
                        onActivated: index => root.collection = model[index].slug
                    }
                    Label { visible: root.kind === "VTODO"; text: "Due date · optional"; color: Theme.muted; font.pixelSize: 12; Layout.topMargin: 8 }
                    SearchField {
                        id: dueField
                        visible: root.kind === "VTODO"
                        Layout.fillWidth: true
                        placeholderText: "YYYY-MM-DD"
                        enabled: root.editable && !root.busy
                    }
                    Label { visible: root.kind === "VEVENT"; text: "When"; color: Theme.muted; font.pixelSize: 12; Layout.topMargin: 8 }
                    Choice {
                        id: modeChoice
                        visible: root.kind === "VEVENT"
                        Layout.fillWidth: true
                        model: ["All day", "Timed"]
                        enabled: root.editable && !root.busy
                        onActivated: index => root.allDay = index === 0
                    }
                    RowLayout {
                        visible: root.kind === "VEVENT"
                        Layout.fillWidth: true
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: "Start date"; color: Theme.muted; font.pixelSize: 12 }
                            SearchField { id: startDateField; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD"; enabled: root.editable && !root.busy }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: "End date"; color: Theme.muted; font.pixelSize: 12 }
                            SearchField { id: endDateField; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD"; enabled: root.editable && !root.busy }
                        }
                    }
                    RowLayout {
                        visible: root.kind === "VEVENT" && !root.allDay
                        Layout.fillWidth: true
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: "Starts"; color: Theme.muted; font.pixelSize: 12 }
                            SearchField { id: startTimeField; Layout.fillWidth: true; placeholderText: "HH:MM"; enabled: root.editable && !root.busy }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: "Ends"; color: Theme.muted; font.pixelSize: 12 }
                            SearchField { id: endTimeField; Layout.fillWidth: true; placeholderText: "HH:MM"; enabled: root.editable && !root.busy }
                        }
                    }
                    Label { text: "Notes · optional"; color: Theme.muted; font.pixelSize: 12; Layout.topMargin: 8 }
                    Controls.TextArea {
                        id: notesField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 78
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        placeholderTextColor: Theme.muted
                        placeholderText: "Details"
                        enabled: root.editable && !root.busy
                        background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.color: notesField.activeFocus ? Theme.accent : Theme.border }
                    }
                }
            }
            Label {
                visible: root.error !== ""
                text: root.error
                color: Theme.danger
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Action { text: "Cancel"; enabled: !root.busy; onClicked: root.close() }
                Action {
                    text: root.busy ? "Saving…" : root.editing ? "Save changes" : "Create"
                    highlighted: true
                    enabled: root.editable && !root.busy && root.collection !== ""
                    onClicked: root.submit()
                }
            }
        }
    }
}
