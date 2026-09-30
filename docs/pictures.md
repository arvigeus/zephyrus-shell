# Pictures

Pictures opens on Wallhaven's toplist and defaults to SFW wallpapers. Wallhaven
supports search, category, sort, time range, aspect ratio, and minimum
resolution filters. Bing Daily is a second provider, with a country filter and
search over the recent images returned by Bing. Each provider supplies its own
filter definitions and wallpaper details to the shared browser.

Wallhaven has three broad content categories: General, Anime, and People. “All
categories” combines them. More specific subjects are tags, so category and
tag stay as separate filters and can be used together. The Tags dropdown has
popular suggestions and an inline search field that filters the suggestions as
you type. Typing also searches Wallhaven's tag directory and replaces the
suggestions with matching tags; selecting a result applies its exact tag ID.
The JSON API supports free-text tag queries and lookup by a known ID, but does
not document tag autocomplete, so tag suggestions use Wallhaven's public HTML
search page. If that page is unavailable, the typed text remains usable as a
Wallhaven query. Queries can use `+tag` to require a tag, `-tag` to exclude
one, and `id:37` for an exact tag ID. The clear button inside the field
restores the suggestions. The visible SFW selector was removed; Wallhaven
requests continue to default to SFW. See
[Wallhaven's search API](https://wallhaven.cc/help/api#search).

The catalogue can switch between a horizontal strip and a grid. A selected
image first uses its uncropped provider preview when available, then fades a
higher-resolution image over it when the displayed size needs one. Favorites
retain their provider identity and are stored in
`$XDG_CONFIG_HOME/zephyrus-shell/pictures-favorites.json` (or
`~/.config/zephyrus-shell/pictures-favorites.json` when `XDG_CONFIG_HOME` is
not set).

Bing Daily uses Microsoft's homepage feed at
[`HPImageArchive.aspx`](https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US).
It is an official Bing endpoint, but Microsoft does not document it as a
supported developer API. The feed exposes only a small recent window (about
two weeks), so Bing search and random selection are limited to those images.
Pictures keeps Bing's title, copyright credit, and Bing detail link with each
image. The images remain copyrighted by their listed owners.

Use **Set wallpaper & lock screen** to download the selected original and apply
it to Zephyrus Shell's desktop on every monitor. No separate wallpaper daemon
is needed. The choice is saved in
`$XDG_CONFIG_HOME/zephyrus-shell/wallpaper.json` and survives closing Pictures
and restarting the shell. Downloaded originals are kept in
`$XDG_DATA_HOME/zephyrus-shell/wallpapers` (or `~/.local/share/zephyrus-shell/wallpapers`).
Downloads have a one-minute deadline; failures restore the button and display
an error. Close Pictures with Escape or select Desktop to see the wallpaper.

To set a random wallpaper at startup in Hyprland, add the backend command to
`hyprland.conf`:

```ini
exec-once = python3 /absolute/path/to/zephyrus-shell/pictures/backend.py --random
```

`--random` chooses a random provider and then a random image from that
provider. Pin a provider with `--provider=wallhaven` or `--provider=bing`; use
`--country=VN` (or another supported country code) to choose the Bing market
when Bing is selected. Wallhaven uses its random API ordering. Bing chooses
from the recent images in its homepage feed. Wallhaven uses the default SFW
filters. The command updates the same saved desktop setting as the module
button, including when it runs before the shell starts.

For use outside Zephyrus Shell, add `--target=desktop`. This retains support
for swww, hyprpaper, KDE Plasma, and GNOME. Start `swww-daemon` or hyprpaper
when using those services. On a custom desktop, set
`ZEPHYRUS_WALLPAPER_COMMAND` to a command with an optional `{path}` argument,
for example `my-wallpaper-tool --file {path}`. An external wallpaper service
cannot replace Zephyrus Shell's own opaque background.

Setting a wallpaper also updates the lock-screen image. Hyprlock reads the
atomic `zephyrus-shell/lock-wallpaper` symlink on the next lock; the image stays
in the Pictures cache, with no second download or wallpaper daemon. This applies
to both shell and external desktop targets.
