import QtQuick
import QtQuick.Controls
import QtTest
import "../../widgets" as W

TestCase {
    name: "ImageGallery"
    width: 800; height: 600; visible: true
    when: windowShown
    property bool moduleClosed: false
    Shortcut { sequence: "Escape"; onActivated: moduleClosed = true }
    Button { id: origin; text: "Open images" }
    W.ImageGallery { id: gallery; parent: testParent }
    Item { id: testParent; anchors.fill: parent }
    function test_keyboard_navigation_and_focus_return() {
        origin.forceActiveFocus();
        gallery.show([{url: Qt.resolvedUrl("../../assets/lucide/film.svg")}, {url: Qt.resolvedUrl("../../assets/lucide/tv.svg")}], 0, "Fixture");
        tryCompare(gallery, "opened", true);
        keyClick(Qt.Key_Right);
        compare(gallery.currentIndex, 1);
        keyClick(Qt.Key_Right);
        compare(gallery.currentIndex, 0);
        keyClick(Qt.Key_End);
        compare(gallery.currentIndex, 1);
        keyClick(Qt.Key_Home);
        compare(gallery.currentIndex, 0);
        keyClick(Qt.Key_Escape);
        tryCompare(gallery, "visible", false);
        verify(!moduleClosed);
        tryCompare(origin, "activeFocus", true);
        compare(gallery.images.length, 0);
    }
}
