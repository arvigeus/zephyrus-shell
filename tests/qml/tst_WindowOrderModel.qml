import QtQuick
import QtTest
import "../../core/windows" as Core

TestCase {
    id: root
    name: "WindowOrderModel"
    QtObject { id: first }
    QtObject { id: second }
    QtObject { id: third }
    QtObject { id: a; property var wayland: first; property var lastIpcObject }
    QtObject { id: b; property var wayland: second; property var lastIpcObject }
    QtObject { id: c; property var wayland: third; property var lastIpcObject }
    Core.WindowOrderModel {
        id: order
        toplevels: [first, second, third]
        clients: [a, b, c]
    }
    SignalSpy { id: updates; target: order; signalName: "windowsChanged" }
    function geometry(x) {
        return {at: [x, 80], monitor: 0, workspace: {id: 1}, floating: false};
    }
    function verifyOrder(expected) {
        compare(order.windows.length, expected.length);
        for (let i = 0; i < expected.length; ++i) compare(order.windows[i], expected[i]);
    }
    function init() {
        order.clients = [a, b, c];
        a.lastIpcObject = geometry(0);
        b.lastIpcObject = geometry(500);
        c.lastIpcObject = geometry(1000);
        wait(0);
        verifyOrder([first, second, third]);
        updates.clear();
    }
    function test_three_window_refresh_publishes_complete_order() {
        // Simulate one IPC response moving the last column to the first slot.
        b.lastIpcObject = geometry(1000);
        c.lastIpcObject = geometry(0);
        // Mixed geometry would put first before third, although the completed
        // desktop order is third, first, second.
        verifyOrder([first, second, third]);
        compare(updates.count, 0);
        a.lastIpcObject = geometry(500);
        wait(0);
        verifyOrder([third, first, second]);
        compare(updates.count, 1);
    }
    function test_scroll_refresh_preserves_order_without_model_changes() {
        a.lastIpcObject = geometry(-1000);
        b.lastIpcObject = geometry(-500);
        c.lastIpcObject = geometry(0);
        wait(0);
        verifyOrder([first, second, third]);
        compare(updates.count, 0);
    }
    function test_new_handles_and_late_metadata() {
        order.clients = [a, b];
        wait(0);
        verifyOrder([first, second, third]);
        c.lastIpcObject = geometry(-500);
        order.clients = [a, b, c];
        wait(0);
        verifyOrder([third, first, second]);
    }
    function test_removed_clients_stop_affecting_the_model() {
        order.clients = [a, b];
        wait(0);
        updates.clear();
        c.lastIpcObject = geometry(-500);
        wait(0);
        verifyOrder([first, second, third]);
        compare(updates.count, 0);
    }
    function test_wayland_handle_changes_and_replacement_client() {
        const replacement = Qt.createQmlObject('import QtQuick; QtObject { property var wayland; property var lastIpcObject }', root);
        replacement.wayland = third;
        replacement.lastIpcObject = geometry(-500);
        order.clients = [a, b, replacement];
        wait(0);
        verifyOrder([third, first, second]);
        replacement.wayland = null;
        wait(0);
        verifyOrder([first, second, third]);
        order.clients = [a, b, c];
        replacement.destroy();
    }
}
