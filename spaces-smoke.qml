//@ pragma UseQApplication
import QtQuick
import Quickshell
import QtTest
import "drawers" as Drawers
import "shell" as Shell
import "core"

ShellRoot {
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 760
        TestCase {
            id: test
            name: "SpacesSearchAndClock"
            visible: true; width: 1000; height: 760
            when: ready
            property bool ready: false
            property int launches: 0
            property string seed: ""
            QtObject {
                id: mutableApplication
                property string name: "Old Name"
                property string genericName: "Editor"
                property var keywords: ["Original"]
                property string icon: ""
            }
            Timer { interval: 250; running: true; onTriggered: test.ready = true }
            Drawers.LibraryDrawer {
                id: library
                width: 390; height: 760
                onSearchRequested: query => { test.seed = query; searchLoader.active = true; }
            }
            Loader {
                id: searchLoader
                anchors.fill: parent
                active: false
                sourceComponent: Drawers.SpaceSearch {
                    initialQuery: test.seed
                    applications: [
                        {name: "Fixture Browser", genericName: "Web", keywords: ["Internet"], icon: "", execute: () => test.launches++},
                        {name: "Fixture Editor", genericName: "Text", keywords: ["Development"], icon: "", execute: () => test.launches++},
                        {name: "Another App", genericName: "", keywords: [], icon: "", execute: () => test.launches++}
                    ]
                    spaces: [{id: "fixture-space", name: "Fixture Music", icon: "music"}]
                }
            }
            Shell.ClockPill {
                id: pill
                x: 650; y: 700
                today: new Date(2026, 9, 2, 12, 0)
                notificationCount: 0
                cloud: ({events: [], tasks: []})
            }
            function init() {
                searchLoader.active = false; launches = 0;
                pill.cloud = {events: [], tasks: []}; pill.notificationCount = 0;
                ShellState.close(); ShellState.toggle("left", "test");
                library.forceActiveFocus();
            }
            function cleanup() { searchLoader.active = false; ShellState.close(); }
            function beginSearch() {
                keyClick(Qt.Key_F);
                tryVerify(() => searchLoader.item !== null);
                tryCompare(searchLoader.item, "catalogReady", true);
                compare(searchLoader.item.query, "f");
                verify(findChild(searchLoader.item, "spacesSearchField").activeFocus);
            }
            function test_type_to_search_and_launch_selected() {
                beginSearch();
                compare(searchLoader.item.matches.length, 3);
                keyClick(Qt.Key_Down);
                compare(searchLoader.item.currentIndex, 1);
                keyClick(Qt.Key_Return);
                compare(launches, 1);
                compare(ShellState.panel, "");
            }
            function test_header_search_button() {
                const button = findChild(library, "spacesSearchButton");
                verify(button !== null);
                mouseClick(button, button.width / 2, button.height / 2);
                tryVerify(() => searchLoader.item !== null);
                compare(searchLoader.item.query, "");
                verify(findChild(searchLoader.item, "spacesSearchField").activeFocus);
            }
            function test_keywords_and_multiple_words() {
                beginSearch();
                const field = findChild(searchLoader.item, "spacesSearchField");
                field.text = "fixture internet";
                compare(searchLoader.item.matches.length, 1);
                compare(searchLoader.item.matches[0].entry.name, "Fixture Browser");
                field.text = "does not exist";
                compare(searchLoader.item.matches.length, 0);
                keyClick(Qt.Key_Return);
                compare(launches, 0);
                compare(ShellState.panel, "left");
            }
            function test_space_navigation_and_escape() {
                beginSearch();
                findChild(searchLoader.item, "spacesSearchField").text = "music";
                keyClick(Qt.Key_Return);
                compare(ShellState.pluginId, "fixture-space");
                compare(ShellState.panel, "module");
            }
            function test_escape_and_empty_query() {
                beginSearch();
                keyClick(Qt.Key_Backspace);
                compare(searchLoader.item.query, "");
                compare(searchLoader.item.matches.length, 0);
                keyClick(Qt.Key_Escape);
                compare(ShellState.panel, "");
            }
            function test_ranking_and_catalogue_replacement() {
                beginSearch();
                const panel = searchLoader.item;
                const field = findChild(panel, "spacesSearchField");
                panel.applications = [
                    {name: "Music Player", keywords: [], icon: ""},
                    {name: "A Player", genericName: "Music", keywords: [], icon: ""},
                    {name: "Music", keywords: [], icon: ""}
                ];
                panel.spaces = [{id: "music", name: "Music", icon: "music"}];
                field.text = "MUSIC";
                compare(panel.matches.length, 4);
                compare(panel.matches[0].kind, "app");
                compare(panel.matches[0].entry.name, "Music");
                compare(panel.matches[1].kind, "space");
                compare(panel.matches[2].entry.name, "Music Player");
                compare(panel.matches[3].entry.name, "A Player");
                panel.applications = [{name: "New App", keywords: ["Music"], icon: ""}];
                panel.spaces = [];
                compare(panel.matches.length, 1);
                compare(panel.matches[0].entry.name, "New App");
                field.text = "  new music  ";
                compare(panel.matches.length, 1);
            }
            function test_metadata_changes_invalidate_search_index() {
                beginSearch();
                const panel = searchLoader.item;
                const field = findChild(panel, "spacesSearchField");
                mutableApplication.name = "Old Name";
                mutableApplication.keywords = ["Original"];
                panel.applications = [mutableApplication]; panel.spaces = [];
                field.text = "original";
                compare(panel.matches.length, 1);
                mutableApplication.keywords = ["Updated"];
                compare(panel.matches.length, 0);
                field.text = "updated";
                compare(panel.matches.length, 1);
                mutableApplication.name = "New Name";
                field.text = "new";
                compare(panel.matches[0].entry.name, "New Name");
            }
            function test_today_indicators() {
                pill.cloud = {tasks: [{due: "2026-10-02"}, {due: "2026-10-03"}, {due: "2026-10-02", completed: true}],
                    events: [{date: "2026-10-01", last_date: "2026-10-03"}, {date: "2026-10-03"}]};
                pill.notificationCount = 2;
                compare(pill.todayTasks, 1); compare(pill.todayEvents, 1);
                verify(findChild(pill, "todayTasksIcon").visible);
                verify(findChild(pill, "todayEventsIcon").visible);
                verify(findChild(pill, "notificationsIcon").visible);
                pill.today = new Date(2026, 9, 4, 0, 0);
                compare(pill.todayTasks, 0); compare(pill.todayEvents, 0);
                pill.notificationCount = 0;
                verify(!pill.hasIndicators);
                pill.today = new Date(2026, 9, 2, 12, 0);
            }
            onCompletedChanged: {
                if (completed) console.log(qtest_results.failCount === 0 && qtest_results.passCount >= 6
                    ? "SPACES CONTROLS PASS" : "SPACES CONTROLS FAIL", qtest_results.passCount, qtest_results.failCount);
            }
        }
    }
}
