import QtQuick
import QtQuick.Controls
import QtTest
import "../../widgets" as W

TestCase {
    name: "WheelScroll"
    visible: true
    width: 480; height: 360
    when: windowShown
    Flickable {
        id: view
        width: 200; height: 200
        contentWidth: 2000; contentHeight: 2000
        W.WheelScroll { id: wheel; view: view }
    }
    W.ScrollArea {
        id: area
        x: 220; width: 200; height: 200
        contentWidth: availableWidth
        Column {
            width: area.availableWidth
            Repeater { model: 30; Button { text: "Clickable row"; width: 180; height: 50 } }
        }
    }
    function init() {
        wheel.motion.stop(); wheel.horizontal=false;
        view.contentX=0; view.contentY=0;
        area.contentItem.contentY=0;
    }
    function test_mouse_notch() {
        mouseWheel(view,100,100,0,-120);
        tryCompare(view,"contentY",320,500);
    }
    function test_rapid_notches_accumulate() {
        wheel.scroll(Qt.point(0,0),Qt.point(0,-120));
        wheel.scroll(Qt.point(0,0),Qt.point(0,-120));
        tryCompare(view,"contentY",640,500);
    }
    function test_pixel_scroll_and_bounds() {
        wheel.scroll(Qt.point(0,-20),Qt.point(0,0));
        compare(view.contentY,30);
        wheel.scroll(Qt.point(0,3000),Qt.point(0,0));
        compare(view.contentY,0);
        wheel.scroll(Qt.point(0,-3000),Qt.point(0,0));
        compare(view.contentY,1800);
    }
    function test_horizontal_mouse_wheel() {
        wheel.horizontal=true;
        mouseWheel(view,100,100,0,-120);
        tryCompare(view,"contentX",320,500);
        compare(view.contentY,0);
    }
    function test_scroll_area_over_button() {
        mouseWheel(area,80,80,0,-120);
        tryCompare(area.contentItem,"contentY",320,500);
    }
}
