import QtQuick
import "../../widgets" as W

W.ArtworkCard {
    property var game: ({})
    property bool selected: false
    property bool installed: false
    text: game.title || ""
    imageSource: game.cover ? game.cover.url : ""
    fallbackIcon: "gamepad-2"
    highlighted: selected
    favorite: !!game.favorite
    badge: installed ? "Installed" : (game.ownedBy || []).length ? "Owned" : ""
    subtitle: [game.releaseDate ? game.releaseDate.slice(0, 4) : "", (game.genres || []).slice(0, 1).join(""), game.libraryEntry ? (game.libraryStores || []).map(store => store === "steam" ? "Steam" : "Epic").join(" / ") : ""].filter(Boolean).join(" · ")
}
