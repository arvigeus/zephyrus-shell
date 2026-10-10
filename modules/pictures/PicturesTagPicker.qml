import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core/theme"
import "../../widgets" as W

Item {
    id: root

    property alias popup: popup
    property var options: []
    property string value: ""
    property string selectedLabel: ""
    property string placeholderText: "Search tags…"
    property string emptyText: "Any tag"
    property var searchResults: []
    property string searchResultsQuery: ""
    property bool searching: false
    property var visibleOptions: matchingOptions(searchField.text, options, searchResults, searchResultsQuery, searching)

    signal valueChosen(string value, string label)
    signal tagSearchRequested(string query)

    implicitWidth: 220
    implicitHeight: 42

    function matchingOptions(searchText, allOptions, foundTags, resultsFor, isSearching) {
        const all = allOptions || [];
        const query = String(searchText || "").trim();
        if (!query) return all;

        const folded = query.toLowerCase();
        const normalizedResultsFor = String(resultsFor || "").toLowerCase();
        if (normalizedResultsFor === folded && isSearching)
            return [{label: "Searching Wallhaven tags…", value: "", selectable: false}];

        if (normalizedResultsFor === folded && foundTags.length) {
            return foundTags.map(tag => ({label: tag.name, value: "id:" + tag.id, tagName: tag.name}));
        }

        const matches = all.filter(option => String(option.value || "") !== "" &&
            (String(option.label || "").toLowerCase().includes(folded) ||
             String(option.value || "").toLowerCase().includes(folded)));
        if (normalizedResultsFor === folded)
            return [{label: "Use \"" + query + "\"", value: query, custom: true}];
        if (!matches.length && isSearching)
            return [{label: "Searching Wallhaven tags…", value: "", selectable: false}];
        if (!matches.some(option => String(option.value || "").toLowerCase() === folded ||
                                    String(option.label || "").toLowerCase() === folded))
            matches.push({label: "Use \"" + query + "\"", value: query, custom: true});
        return matches;
    }

    function displayValue() {
        if (selectedLabel) return selectedLabel;
        const option = (options || []).find(item => String(item.value || "") === value);
        return option ? option.label : value;
    }

    function choose(value, label) {
        const selectedText = value ? (label || value) : "";
        searchField.text = selectedText;
        tagSearchDelay.stop();
        valueChosen(value, label || value);
        popup.close();
    }

    function chooseTypedSearch() {
        const query = searchField.text.trim();
        if (!query) {
            choose("", emptyText);
            return;
        }
        const folded = query.toLowerCase();
        const exactTag = searchResultsQuery.toLowerCase() === folded
            ? searchResults.find(tag => String(tag.name || "").toLowerCase() === folded)
            : null;
        if (exactTag) {
            choose("id:" + exactTag.id, exactTag.name);
            return;
        }
        const exact = (options || []).find(option =>
            String(option.value || "").toLowerCase() === folded ||
            String(option.label || "").toLowerCase() === folded);
        choose(exact ? exact.value : query, exact ? exact.label : query);
    }

    Button {
        id: trigger
        anchors.fill: parent
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: root.value ? "Tags: " + root.displayValue() : "Tags"
        onClicked: {
            if (popup.visible) {
                popup.close();
                return;
            }
            searchField.text = root.value
                ? (root.selectedLabel || (String(root.value).startsWith("id:") ? "" : root.value))
                : "";
            popup.open();
            Qt.callLater(() => {
                searchField.forceActiveFocus();
                if (searchField.text.trim()) tagSearchDelay.restart();
            });
        }

        contentItem: RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.value ? (root.selectedLabel || root.displayValue()) : root.emptyText
                color: root.value ? Theme.text : Theme.muted
                font.family: Theme.font; font.pixelSize: Theme.sp(14)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }
            W.Icon {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                name: "chevron-down"
            }
        }
        background: Rectangle {
            radius: Theme.controlRadius
            color: trigger.hovered ? Theme.raised : Theme.surface
            border.color: trigger.activeFocus || popup.opened ? Theme.accent : "transparent"
        }
    }

    Popup {
        id: popup
        parent: root
        popupType: Popup.Item
        y: root.height + 4
        width: Math.max(root.width, 260)
        padding: 6
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        implicitHeight: popupContent.implicitHeight + padding * 2

        background: Rectangle {
            radius: Theme.controlRadius
            color: Theme.surface
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            id: popupContent
            spacing: 6

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                W.SearchField {
                    id: searchField
                    anchors.fill: parent
                    rightPadding: 42
                    placeholderText: root.placeholderText
                    Accessible.name: "Search Wallhaven tags"
                    onTextChanged: if (popup.opened) tagSearchDelay.restart()
                    onAccepted: root.chooseTypedSearch()
                }

                W.IconButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    iconSize: 16
                    iconName: "x"
                    text: "Clear tag search"
                    visible: searchField.text.length > 0
                    onClicked: {
                        searchField.clear();
                        searchField.forceActiveFocus();
                    }
                }
            }

            ListView {
                id: optionsView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(240, Math.max(38, root.visibleOptions.length * 36))
                clip: true
                model: root.visibleOptions
                currentIndex: -1
                keyNavigationEnabled: true
                keyNavigationWraps: false
                ScrollBar.vertical: ScrollBar {}

                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 36
                    hoverEnabled: true
                    enabled: modelData.selectable !== false
                    highlighted: hovered || optionsView.currentIndex === index
                    onClicked: root.choose(String(modelData.value || ""), String(modelData.label || ""))

                    contentItem: Text {
                        text: modelData.label
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.sp(14)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                    }
                    background: Rectangle {
                        color: parent.highlighted ? Theme.raised : "transparent"
                        radius: 4
                    }
                }
            }
        }
    }

    Timer {
        id: tagSearchDelay
        interval: 300
        onTriggered: root.tagSearchRequested(searchField.text.trim())
    }
}
