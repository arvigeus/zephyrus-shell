import QtQuick
import Quickshell
import QtTest
import "../../shell" as Shell
import "../../widgets" as W
import "../../core"

Scope {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 200
        TestCase {
            id: test
            name: "TrayButton"
            visible: true; width: 400; height: 200
            when: ready
            onCompletedChanged: {
                if (completed) console.log(qtest_results.failCount === 0 && qtest_results.passCount >= 8
                    ? "TRAY CONTROLS PASS" : "TRAY CONTROLS FAIL", qtest_results.passCount, qtest_results.failCount);
            }
            property bool ready: false
            Timer { interval: 250; running: true; onTriggered: test.ready = true }
            property int activations: 0
            property int secondaryActivations: 0
            property int menus: 0
            property int wheelDelta: 0
            property var menuPosition: null
            QtObject { id: testBar; property var contentItem: test }
            Flickable {
                id: view
                x: 30; y: 20; width: 140; height: 34
                contentWidth: 300; contentHeight: 34
                W.WheelScroll { view: view; horizontal: true }
                Shell.TrayButton { id: button; barWindow: testBar; trayItem: ({id:"fixture", title:"Fixture", tooltipTitle:"", icon:""}) }
            }
            function init() {
                activations = 0; secondaryActivations = 0; menus = 0; wheelDelta = 0; menuPosition = null;
                view.contentX = 0;
                button.x = 0;
                button.trayItem = {
                    id: "zephyrus-tray-fixture", title: "Fixture", tooltipTitle: "", icon: "", onlyMenu: false, hasMenu: true,
                    activate: () => test.activations++, secondaryActivate: () => test.secondaryActivations++,
                    display: (window, x, y) => { test.menus++; test.menuPosition = {window: window, x: x, y: y}; },
                    scroll: (delta, horizontal) => test.wheelDelta = delta
                };
                ShellState.monitor = "test";
                ShellState.openModule("tray-fixture-module");
            }
            function cleanup() { ShellState.showDesktop(); }
            function test_right_while_tooltip_visible() {
                mouseMove(button, 17, 17);
                tryCompare(button, "toolTipVisible", true, 2000);
                mouseClick(button, 17, 17, Qt.RightButton);
                tryCompare(test, "menus", 1);
                compare(button.toolTipVisible, false);
                compare(activations, 0);
            }
            function test_primary() {
                mouseClick(button, 17, 17, Qt.LeftButton);
                tryCompare(test, "activations", 1);
                compare(menus, 0);
                compare(ShellState.moduleId, "");
            }
            function test_missing_theme_icon() {
                button.trayItem = Object.assign({}, button.trayItem,
                    {icon: "image://icon/zephyrus-nonexistent-tray-fixture"});
                verify(button.missingThemeIcon);
                compare(button.contentItem.children[0].source.toString(), "");
                verify(button.contentItem.children[1].visible);
            }
            function test_right() {
                mouseClick(button, 17, 17, Qt.RightButton);
                tryCompare(test, "menus", 1);
                compare(activations, 0);
                compare(menuPosition.window, testBar);
                compare(menuPosition.x, 30);
                compare(menuPosition.y, 54);
                compare(ShellState.moduleId, "");
            }
            function test_menu_only_primary() {
                button.trayItem = Object.assign({}, button.trayItem, {onlyMenu: true});
                mouseClick(button, 17, 17, Qt.LeftButton);
                tryCompare(test, "menus", 1);
                compare(activations, 0);
            }
            function test_middle() {
                mouseClick(button, 17, 17, Qt.MiddleButton);
                tryCompare(test, "secondaryActivations", 1);
                compare(activations, 0);
                compare(menus, 0);
            }
            function test_no_menu() {
                button.trayItem = Object.assign({}, button.trayItem, {hasMenu: false});
                mouseClick(button, 17, 17, Qt.RightButton);
                wait(100);
                compare(menus, 0);
                compare(activations, 0);
            }
            function test_wheel() {
                button.x = 60;
                view.contentX = 50;
                mouseWheel(button, 17, 17, 0, 120);
                tryCompare(test, "wheelDelta", 120);
                wait(120);
                compare(view.contentX, 50);
            }
        }

    }
}
