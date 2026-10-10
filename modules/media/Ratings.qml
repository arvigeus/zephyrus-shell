import QtQuick
import QtQuick.Layouts
import "RatingLinks.js" as RatingLinks
import "../../widgets" as W
import "../../core"

Flow {
    id: root
    property var host
    property var ratings: []
    property var title: ({})
    spacing: 18
    function icon(r) {
        const source = RatingLinks.source(r);
        const score = parseFloat(r.value);
        if (source === "rt") return score >= 75 ? "rt_certified" : score >= 60 ? "rt_fresh" : "rt_rotten";
        if (source === "rt_audience") return score >= 90 ? "rt_audience_hot" : score >= 60 ? "rt_audience_positive" : "rt_audience_negative";
        return ({imdb:"imdb", myanimelist:"mal", tmdb:"tmdb", metacritic:"metacritic"})[source] || "";
    }
    Repeater {
        model: RatingLinks.ordered(root.ratings).filter(r => !!root.icon(r))
        W.Action {
            id: ratingButton
            required property var modelData
            readonly property string ratingIcon: root.icon(modelData)
            text: modelData.source + ": " + modelData.value
            toolTip: text
            implicitWidth: contentItem.implicitWidth + 8; implicitHeight: 32
            padding: 4
            onClicked: Browser.open(RatingLinks.page(modelData, root.title), root.title.kind === "tv" ? "series" : "movies", "", root.host)
            contentItem: RowLayout {
                spacing: 6
                W.AppIcon { artwork: Qt.resolvedUrl("../../assets/ratings/rating_" + ratingButton.ratingIcon + (ratingButton.ratingIcon === "mal" ? ".svg" : ".png")); Layout.preferredWidth: 32; Layout.preferredHeight: 24; Accessible.name: ratingButton.modelData.source }
                W.Label { text: String(ratingButton.modelData.value); font.bold: true }
            }
        }
    }
}
