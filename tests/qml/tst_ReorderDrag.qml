import QtQuick
import QtTest
import "../../widgets" as W

TestCase {
    id: root
    name: "ReorderDrag"
    width: 320; height: 160; visible: true
    when: windowShown
    property int clicks: 0
    property int starts: 0
    property int moves: 0
    property int finishes: 0
    property bool committed: false
    property point lastPosition: Qt.point(0, 0)
    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: 600; contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        W.Action {
            id: button
            x: 30; y: 30; width: 42
            text: "Window"
            onClicked: root.clicks++
            W.ReorderDrag {
                id: drag
                onDragStarted: root.starts++
                onDragMoved: position => { root.moves++; root.lastPosition = position; }
                onDragFinished: commit => { root.finishes++; root.committed = commit; }
            }
        }
    }
    function init() {
        view.contentX = 0;
        drag.enabled = true;
        clicks = 0; starts = 0; moves = 0; finishes = 0; committed = false;
        lastPosition = Qt.point(0, 0);
    }
    function test_1_click_is_not_a_drag() {
        mouseClick(button, 21, 21);
        compare(clicks, 1);
        compare(starts, 0);
        compare(finishes, 0);
    }
    function test_2_release_commits_without_clicking() {
        mousePress(button, 21, 21);
        mouseMove(button, 40, 21, 20);
        mouseMove(button, 100, 21, 20);
        tryCompare(root, "starts", 1);
        verify(moves > 0);
        compare(finishes, 0);
        mouseRelease(button, 100, 21);
        compare(finishes, 1);
        verify(committed);
        compare(lastPosition.x, 130);
        compare(lastPosition.y, 51);
        compare(clicks, 0);
        compare(view.contentX, 0);
    }
    function test_3_lost_grab_cancels() {
        mousePress(button, 21, 21);
        mouseMove(button, 40, 21, 20);
        mouseMove(button, 100, 21, 20);
        tryCompare(root, "starts", 1);
        drag.enabled = false;
        compare(finishes, 1);
        verify(!committed);
        mouseRelease(button, 100, 21);
        compare(clicks, 0);
    }
    function test_4_release_uses_final_pointer_position_data() {
        return [
            {tag: "new insertion target", x: 140, y: 21},
            {tag: "outside list", x: 100, y: 170},
        ];
    }
    function test_4_release_uses_final_pointer_position(data) {
        mousePress(button, 21, 21);
        mouseMove(button, 40, 21, 20);
        mouseMove(button, 100, 21, 20);
        tryCompare(root, "starts", 1);
        mouseRelease(button, data.x, data.y);
        compare(finishes, 1);
        verify(committed);
        // RunningApps needs this position to accept the final insertion target
        // or reject a release outside its bounds.
        compare(lastPosition.x, button.x + data.x);
        compare(lastPosition.y, button.y + data.y);
        compare(clicks, 0);
    }
}
