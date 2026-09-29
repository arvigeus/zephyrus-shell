import "." as W

W.HoldAction {
    property bool torrent: false
    iconName: "trash-2"
    text: torrent ? "Hold to delete torrent and all its downloaded files" : "Hold to delete local file"
}
