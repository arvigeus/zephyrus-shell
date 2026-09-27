import QtQuick
import QtTest
import "../../widgets" as W

TestCase {
    id: testRoot
    name: "CrossfadeImage"
    visible: true; width: 640; height: 320
    when: windowShown
    property url chainedSource: ""
    readonly property url previewSource: Qt.resolvedUrl("../../assets/lucide/film.svg")
    readonly property url fullSource: Qt.resolvedUrl("../../assets/lucide/tv.svg")
    readonly property url thirdSource: Qt.resolvedUrl("../../assets/lucide/image.svg")
    W.CrossfadeImage { id: image; y: 150; width: 80; height: 80; duration: 120 }
    W.CrossfadeImage { id: overlayImage; y: 30; width: 80; height: 80; duration: 420; fadeInOnTop: true }
    W.CrossfadeImage { id: rapidImage; x: 240; y: 30; width: 80; height: 80; duration: 420; fadeInOnTop: true }
    W.CrossfadeImage {
        id: chainedImage
        x: 120; y: 30; width: 80; height: 80; duration: 120
        source: testRoot.chainedSource
        fadeInOnTop: true
        onDisplayedSourceChanged: {
            if (displayedSource.toString() === testRoot.previewSource.toString())
                testRoot.chainedSource = testRoot.fullSource;
        }
    }
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
    function test_reset_on_source_change_drops_previous_art_immediately() {
        image.resetOnSourceChange = true;
        image.source = Qt.resolvedUrl("../../assets/lucide/film.svg");
        tryCompare(image, "displayedSource", image.source);
        image.source = Qt.resolvedUrl("../../assets/lucide/tv.svg");
        verify(!image.displayedSource.toString() || image.displayedSource.toString() === image.source.toString());
        const buffers = image.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        compare(buffers.filter(b => b.source.toString().endsWith("film.svg")).length, 0);
        tryCompare(image, "hasImage", true);
        compare(image.displayedSource.toString(), image.source.toString());
        image.resetOnSourceChange = false;
    }
    function test_new_image_fades_over_visible_preview() {
        overlayImage.source = Qt.resolvedUrl("../../assets/lucide/film.svg");
        tryCompare(overlayImage, "hasImage", true);
        overlayImage.source = Qt.resolvedUrl("../../assets/lucide/tv.svg");
        tryCompare(overlayImage, "transitioning", true);
        const buffers = overlayImage.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        const oldImage = buffers.find(c => c.source.toString() === overlayImage.displayedSource.toString());
        verify(!!oldImage);
        compare(oldImage.opacity, 1);
        wait(150);
        compare(oldImage.opacity, 1);
        tryCompare(overlayImage, "transitioning", false);
        compare(overlayImage.displayedSource.toString(), overlayImage.source.toString());
        compare(buffers.filter(b => !!b.source.toString()).length, 1);
    }
    function test_preview_can_request_full_resolution_from_display_callback() {
        chainedSource = previewSource;
        tryCompare(chainedImage, "displayedSource", fullSource);
        compare(chainedImage.source.toString(), fullSource.toString());
        tryCompare(chainedImage, "transitioning", false);
        const buffers = chainedImage.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        verify(buffers.filter(b => !!b.source.toString()).length === 1,
               JSON.stringify(buffers.map(b => ({name:b.objectName, source:b.source.toString(), opacity:b.opacity})))
               + " frontIsA=" + chainedImage.frontIsA + " transitioning=" + chainedImage.transitioning);
    }
    function test_superseded_fade_never_displays_intermediate_image() {
        rapidImage.source = previewSource;
        tryCompare(rapidImage, "displayedSource", previewSource);
        rapidImage.source = fullSource;
        tryCompare(rapidImage, "transitioning", true);
        rapidImage.source = thirdSource;
        const buffers = rapidImage.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        compare(buffers.filter(b => b.source.toString() === fullSource.toString()).length, 0);
        tryCompare(rapidImage, "displayedSource", thirdSource);
        tryCompare(rapidImage, "transitioning", false);
        compare(buffers.filter(b => !!b.source.toString()).length, 1);
    }
    function test_clear_discards_previous_selection_during_fade() {
        rapidImage.source = previewSource;
        tryCompare(rapidImage, "displayedSource", previewSource);
        rapidImage.source = fullSource;
        tryCompare(rapidImage, "transitioning", true);
        rapidImage.clear();
        compare(rapidImage.transitioning, false);
        compare(rapidImage.hasImage, false);
        const buffers = rapidImage.children.filter(c => c.objectName === "imageA" || c.objectName === "imageB");
        compare(buffers.filter(b => !!b.source.toString()).length, 0);
        rapidImage.prepare();
        tryCompare(rapidImage, "displayedSource", fullSource);
    }
}
