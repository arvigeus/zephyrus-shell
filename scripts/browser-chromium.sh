#!/usr/bin/env bash
# Open one shell URL in a disposable Chromium app window with uBlock Origin Lite.
set -euo pipefail

if [[ $# -ne 1 || -z $1 ]]; then
    echo "Usage: browser-chromium.sh URL" >&2
    exit 2
fi

browser=${ZEPHYRUS_CHROMIUM:-chromium}
if ! command -v -- "$browser" >/dev/null; then
    echo "Chromium not found: $browser" >&2
    exit 1
fi

extension=${ZEPHYRUS_ADBLOCK_DIR:-}
if [[ -z $extension ]]; then
    extension_base="${XDG_CONFIG_HOME:-$HOME/.config}/chromium/Default/Extensions/ddkjiahejlhfcafbddmgiahcphecmpfh"
    if [[ -d $extension_base ]]; then
        # Select the newest installed version that contains an extension manifest.
        IFS= read -r -d '' extension < <(
            find "$extension_base" -mindepth 2 -maxdepth 2 -type f -name manifest.json -printf '%h\0' |
                sort -z -V | tail -z -n 1
        ) || true
    fi
fi
if [[ -z $extension || ! -f $extension/manifest.json ]]; then
    echo "uBlock Origin Lite not found. Install it in Chromium's Default profile or set ZEPHYRUS_ADBLOCK_DIR to its unpacked directory." >&2
    exit 1
fi

profile_base="${XDG_CACHE_HOME:-$HOME/.cache}/zephyrus-shell/browser"
mkdir -p -- "$profile_base"
profile=$(mktemp -d "$profile_base/profile.XXXXXXXX")
browser_pid=
cleanup() {
    if [[ -n $browser_pid ]] && kill -0 "$browser_pid" 2>/dev/null; then
        kill "$browser_pid" 2>/dev/null || true
        wait "$browser_pid" 2>/dev/null || true
    fi
    rm -rf -- "$profile"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$browser" \
    --user-data-dir="$profile" \
    --load-extension="$extension" \
    --disable-extensions-except="$extension" \
    --app="$1" \
    --start-fullscreen \
    --no-first-run &
browser_pid=$!
wait "$browser_pid"
