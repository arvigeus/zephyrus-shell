#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
games_test_root=$(mktemp -d)
trap 'rm -rf -- "$games_test_root"' EXIT
export XDG_CONFIG_HOME="$games_test_root/config" XDG_DATA_HOME="$games_test_root/data" XDG_CACHE_HOME="$games_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export HOME="$games_test_root/home" GAMES_SMOKE_LAUNCH_LOG="$games_test_root/steam-launch.log"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME/zephyrus-shell" "$HOME/.steam/steam/steamapps/common/Smoke Game" "$games_test_root/bin" tests/artifacts
export PATH="$games_test_root/bin:$PATH"
cat > "$games_test_root/bin/steam" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GAMES_SMOKE_LAUNCH_LOG"
SH
chmod +x "$games_test_root/bin/steam"
cat > "$HOME/.steam/steam/steamapps/libraryfolders.vdf" <<EOF
"libraryfolders"
{
    "0" { "path" "$HOME/.steam/steam" }
}
EOF
cat > "$HOME/.steam/steam/steamapps/appmanifest_123.acf" <<'EOF'
"AppState"
{
    "appid" "123"
    "name" "Smoke Game"
    "StateFlags" "4"
    "installdir" "Smoke Game"
}
EOF

timeout 15s dbus-run-session quickshell -p "$PWD/games-smoke.qml" --no-color > "$games_test_root/setup-log" 2>&1 || { cat "$games_test_root/setup-log"; exit 1; }
rg -q 'GAMES PASS' "$games_test_root/setup-log"

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
from games.backend import GamesBackend, normalize_igdb_game, protondb_url

root = Path(os.environ["XDG_DATA_HOME"]) / "zephyrus-shell/games"
config = Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/games.json"
config.write_text(json.dumps({"igdb_client_id": "smoke-id", "igdb_client_secret": "smoke-secret", "steam_api_key": "", "steam_id": ""}))
backend = GamesBackend(data=root, config=config)
record = normalize_igdb_game({
    "id": 123, "name": "Smoke Game", "summary": "A local Games module smoke fixture.",
    "released": "2024-01-01",
    "genres": [{"name": "Adventure"}], "platforms": [{"name": "Linux"}],
    "websites": [{"url": "https://store.steampowered.com/app/123/"},
                 {"type": 1, "url": "https://example.org/smoke-game"}],
}, "games-smoke-local-id")
game = backend._save_game(123, record)
from media.local import LocalLibrary
local_archive = root / "local-game.zip"
local_archive.write_bytes(b"local game fixture")
LocalLibrary(Path(os.environ["XDG_DATA_HOME"]) / "zephyrus-shell/media").add(
    {"kind": "game", "id": game["id"], "title": game["title"]}, local_archive, move=True)
art = Path(os.environ["XDG_CACHE_HOME"]) / "games-cover.svg"
art.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="500"><rect width="800" height="500" fill="#18343f"/><circle cx="590" cy="210" r="145" fill="#cfaf88"/><path d="M0 470L320 170l190 210 140-130 150 220z" fill="#1a242e"/></svg>')
game["cover"] = {"url": art.as_uri()}
game["artwork"] = [{"url": art.as_uri()}]
key = "browse:v4:" + hashlib.sha256(json.dumps(["igdb", "", {"ordering": "-added"}, 0], sort_keys=True).encode()).hexdigest()
backend._cache_put(key, {"items": [game], "next": None, "setupRequired": False, "warning": "",
                         "provider": "igdb", "providerName": "IGDB"})
backend._cache_put("detail:v3:igdb:123", game)
backend._cache_put("protondb:v1:123", {
    "available": True, "tier": "gold", "label": "Gold", "total": 12,
    "url": protondb_url("123"), "appId": "123",
})
PY

timeout 15s dbus-run-session quickshell -p "$PWD/games-library-smoke.qml" --no-color > "$games_test_root/library-log" 2>&1 || { cat "$games_test_root/library-log"; exit 1; }
cat "$games_test_root/setup-log" "$games_test_root/library-log"
rg -q 'GAMES PASS: entry point' "$games_test_root/setup-log"
rg -q 'GAMES PASS: catalogue' "$games_test_root/library-log"
for attempt in {1..20}; do
    if rg -q '^-applaunch 123$' "$GAMES_SMOKE_LAUNCH_LOG" 2>/dev/null; then break; fi
    sleep 0.05
done
rg -q '^-applaunch 123$' "$GAMES_SMOKE_LAUNCH_LOG"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|GAMES FAIL|Cannot load|module could not load' "$games_test_root/setup-log" "$games_test_root/library-log"; then exit 1; fi
