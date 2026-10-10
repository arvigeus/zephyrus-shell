import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "../../core/theme"
import "../../widgets" as W
import "../../shell" as Shell

Scope {
    FloatingWindow {
        implicitWidth: 500; implicitHeight: 300
        TestCase {
            id: test
            name: "Action"
            width: 500; height: 300; visible: true
            when: ready
            property bool ready: false
            Timer { interval: 250; running: true; onTriggered: test.ready = true }
            onCompletedChanged: if (completed) console.log(qtest_results.failCount === 0 && qtest_results.passCount >= 9
                ? "ACTION CONTROLS PASS" : "ACTION CONTROLS FAIL", qtest_results.passCount, qtest_results.failCount)
            property var originalSettings
            W.Action { id: labeled; x: 20; y: 20; text: "Find"; ToolTip.delay: 0 }
            W.Action { id: withIcon; x: 150; y: 20; text: "Search"; iconName: "search"; ToolTip.delay: 0 }
            W.IconButton { id: iconOnly; x: 300; y: 20; text: "Search"; iconName: "search"; ToolTip.delay: 0 }
            W.Action { id: helpful; x: 20; y: 100; text: "Screenshot"; toolTip: "Capture an area now"; ToolTip.delay: 0 }
            // Existing callers also use the attached property for contextual hints.
            W.Action { id: attached; x: 200; y: 100; text: "Stay awake"; ToolTip.text: "Allow dimming while preventing sleep"; ToolTip.delay: 0 }
            W.HoldAction { id: hold; x: 20; y: 180; text: "Power off"; showLabel: true; ToolTip.text: "Hold for 2 seconds to power off"; ToolTip.delay: 0 }
            Shell.BarAction { id: labeledPill; x: 200; y: 180; text: "Spaces"; iconName: "grid-vertical" }
            Shell.BarAction {
                id: iconPill
                x: 400; y: 180; text: "Clipboard history"; toolTip: text
                contentItem: W.Icon { name: "clipboard" }
            }

            function initTestCase() {
                originalSettings = Theme.settings;
                const settings = JSON.parse(JSON.stringify(originalSettings));
                settings.mode = "light";
                Theme.settings = settings;
                mouseMove(test, 480, 280);
                wait(150);
            }
            function cleanupTestCase() { Theme.settings = originalSettings; }
            function cleanup() {
                mouseMove(test, 480, 280);
                test.forceActiveFocus();
                wait(150);
            }
            function test_bar_tooltips() {
                mouseMove(labeledPill, labeledPill.width / 2, labeledPill.height / 2);
                tryCompare(labeledPill, "hovered", true);
                wait(900);
                compare(labeledPill.toolTipVisible, false);
                mouseMove(iconPill, iconPill.width / 2, iconPill.height / 2);
                tryCompare(iconPill, "toolTipVisible", true, 2000);
                iconPill.dismissToolTip();
                compare(iconPill.toolTipVisible, false);
            }
            function test_tooltips_data() {
                return [{tag: "label", control: labeled, hint: ""},
                        {tag: "icon and label", control: withIcon, hint: ""},
                        {tag: "icon only", control: iconOnly, hint: "Search"},
                        {tag: "helpful", control: helpful, hint: "Capture an area now"},
                        {tag: "attached hint", control: attached, hint: "Allow dimming while preventing sleep"},
                        {tag: "hold instruction", control: hold, hint: "Hold for 2 seconds to power off"}];
            }
            function test_tooltips(data) {
                const control = data.control;
                mouseMove(control, control.width / 2, control.height / 2);
                tryCompare(control, "hovered", true);
                compare(control.ToolTip.text, data.hint);
                compare(control.ToolTip.visible, !!data.hint);
                mouseMove(test, 480, 280);
                control.forceActiveFocus(Qt.TabFocusReason);
                compare(control.ToolTip.visible, !!data.hint);
            }
            function test_light_hover_animation() {
                mouseMove(labeled, labeled.width / 2, labeled.height / 2);
                tryCompare(labeled, "hovered", true);
                // Check the intermediate frames: the final color alone misses the flash.
                for (let i = 0; i < 8; ++i) {
                    wait(15);
                    const color = labeled.background.color;
                    verify(color.r >= Theme.surface.r - 0.01 && color.g >= Theme.surface.g - 0.01 && color.b >= Theme.surface.b - 0.01,
                           "Hover faded through a dark color: " + color);
                }
                tryCompare(labeled.background, "color", Theme.surface);
                mouseMove(test, 480, 280);
                for (let i = 0; i < 8; ++i) {
                    wait(15);
                    const color = labeled.background.color;
                    verify(color.r >= Theme.surface.r - 0.01 && color.g >= Theme.surface.g - 0.01 && color.b >= Theme.surface.b - 0.01,
                           "Hover exit faded through a dark color: " + color);
                }
                tryCompare(labeled.background, "color", labeled.idleColor);
            }
        }
    }
}
