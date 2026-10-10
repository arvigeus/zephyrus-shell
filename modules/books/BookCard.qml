import QtQuick
import "../../widgets" as W

W.ArtworkCard {
    property var book: ({})
    text: book.title || "Untitled work"
    imageSource: book.coverSmall || ""
    fallbackIcon: "book-open"
    Accessible.name: [text, (book.authors || []).map(author => author.name).filter(Boolean).join(", "), book.firstPublishYear || ""].filter(Boolean).join(". ")
}
