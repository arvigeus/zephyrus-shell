import QtQuick
import "RatingLinks.js" as RatingLinks
import QtQuick.Layouts
import "../widgets" as W
import "../core"
Flow {
    id: root
    property var ratings: []
    property var title: ({})
    function page(r) { return RatingLinks.page(r, title); }
    spacing: 18
    function icon(r) {
        const source = r.source.toLowerCase();
        const score = parseFloat(r.value);
        if (source === "imdb" || source === "internet movie database") return "imdb";
        if (source === "tmdb") return "tmdb";
        if (source === "metacritic") return "metacritic";
        if (["rotten tomatoes","tomatoes","rt"].includes(source)) return score >= 75 ? "rt_certified" : score >= 60 ? "rt_fresh" : "rt_rotten";
        if (["popcorn","tomatoesaudience","rt_audience"].includes(source)) return score >= 90 ? "rt_audience_hot" : score >= 60 ? "rt_audience_positive" : "rt_audience_negative";
        return "";
    }
    Repeater {
        model: RatingLinks.ordered(root.ratings).filter(r => !!root.icon(r))
        W.Action {
            id: ratingButton
            required property var modelData
            text: ratingButton.modelData.source + ": " + modelData.value
            implicitWidth: contentItem.implicitWidth + 8; implicitHeight: 32
            padding: 4
            onClicked: Qt.openUrlExternally(root.page(modelData))
            contentItem: RowLayout {
            spacing: 6
            W.AppIcon { artwork: Qt.resolvedUrl("../assets/ratings/rating_" + root.icon(ratingButton.modelData) + ".png"); Layout.preferredWidth: 32; Layout.preferredHeight: 24; Accessible.name: ratingButton.modelData.source }
            W.Label { visible: !root.icon(ratingButton.modelData); text: ratingButton.modelData.source; color: Theme.muted }
            W.Label { text: String(ratingButton.modelData.value); font.bold: true }
            }
        }
    }
}
