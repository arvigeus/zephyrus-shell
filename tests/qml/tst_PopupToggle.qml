import QtQuick
import QtQuick.Controls
import QtTest
import "../../widgets" as W
import "../../modules/media" as Media
import "../../modules/pictures" as Pictures

TestCase {
    id: test
    name: "PopupToggle"
    width: 700; height: 600; visible: true
    when: windowShown
    W.Choice { id: choice; x: 20; y: 20; width: 200; model: ["First", "Second"] }
    Media.SplitButton { id: split; x: 20; y: 80; text: "Watch"; options: ["First", "Second"] }
    Pictures.PicturesTagPicker { id: tags; x: 20; y: 140; width: 220; height: 42; options: [{label: "Any", value: ""}, {label: "Nature", value: "nature"}] }

    function test_select_data() {
        return [{tag: "choice", trigger: choice, popup: choice.popup},
                {tag: "split", trigger: split.children.find(item => item.text === "Choose watch"), popup: split.popup}];
    }
    function test_select(data) {
        mouseClick(data.trigger, data.trigger.width / 2, data.trigger.height / 2);
        tryCompare(data.popup, "visible", true);
        const getOption = () => data.tag === "choice" ? data.popup.contentItem.itemAtIndex(1) : data.popup.itemAt(1);
        tryVerify(() => getOption() !== null);
        const option = getOption();
        mouseClick(option, option.width / 2, option.height / 2);
        tryCompare(data.popup, "visible", false);
        compare(data.tag === "choice" ? choice.currentIndex : split.currentIndex, 1);
    }

    function cleanup() {
        choice.popup.close();
        split.popup.close();
        tags.popup.close();
    }

    function test_toggle_data() {
        return [{tag: "choice", trigger: choice, popup: choice.popup},
                {tag: "split", trigger: split.children.find(item => item.text === "Choose watch"), popup: split.popup},
                {tag: "tags", trigger: tags, popup: tags.popup}];
    }
    function test_toggle(data) {
        const target = data.trigger;
        const popup = data.popup;
        verify(target !== undefined);
        verify(popup !== undefined);
        for (let i = 0; i < 3; i++) {
            mouseClick(target, target.width / 2, target.height / 2);
            tryCompare(popup, "visible", true);
            // Check the press separately: dismissing here would reopen on release.
            mousePress(target, target.width / 2, target.height / 2);
            compare(popup.visible, true);
            mouseRelease(target, target.width / 2, target.height / 2);
            tryCompare(popup, "visible", false);
        }
        mouseClick(target, target.width / 2, target.height / 2);
        tryCompare(popup, "visible", true);
        mouseClick(test, 680, 580);
        tryCompare(popup, "visible", false);
        mouseClick(target, target.width / 2, target.height / 2);
        tryCompare(popup, "visible", true);
        keyClick(Qt.Key_Escape);
        tryCompare(popup, "visible", false);
    }
}
