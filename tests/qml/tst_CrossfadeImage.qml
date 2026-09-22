import QtQuick
import QtTest
import "../../widgets" as W

TestCase {
    name: "CrossfadeImage"
    visible: true; width: 640; height: 320
    when: windowShown
    W.CrossfadeImage { id: image; y: 150; width: 80; height: 80; duration: 120 }
    function test_first_image_immediate_then_crossfade() {
        image.source=Qt.resolvedUrl("../../assets/lucide/film.svg");
        tryCompare(image,"hasImage",true);
        compare(image.imageOpacity,1);
        verify(!image.transitioning);
        image.source=Qt.resolvedUrl("../../assets/lucide/tv.svg");
        tryCompare(image,"transitioning",true);
        tryCompare(image,"transitioning",false);
        compare(image.displayedSource.toString(),image.source.toString());
        const buffers=image.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        compare(buffers.filter(b => !!b.source.toString()).length,1);
    }
}
