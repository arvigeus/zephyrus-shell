#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
language_test_root=$(mktemp -d)
trap 'rm -rf -- "$language_test_root"' EXIT
mkdir -p "$language_test_root/bin" "$language_test_root/config/zephyrus-shell" "$language_test_root/runtime" tests/artifacts
export ZEPHYRUS_LANGUAGE_FIXTURE="$language_test_root/state.json"
cat > "$language_test_root/bin/language-tool" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
import time
from pathlib import Path
path = Path(os.environ['ZEPHYRUS_LANGUAGE_FIXTURE'])
state = json.loads(path.read_text()) if path.exists() else {'available': os.environ.get('ZEPHYRUS_LANGUAGE_READY') != '0', 'secondary': 'bg', 'language': 'en', 'running': False, 'laptop': 'en'}
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'language-fixture':
    time.sleep(.1)
    state['laptop'] = args[0]
    path.write_text(json.dumps(state))
    sys.exit()
if name == 'hyprctl':
    if args[0] == 'switchxkblayout':
        state['language'] = state['laptop'] = 'bg' if args[-1] == '1' else 'en'
        path.write_text(json.dumps(state))
        sys.exit()
    def keyboard(name, main, language):
        return dict(name=name, main=main, layout='us,bg', active_layout_index=int(language == 'bg'))
    result = {'keyboards': [keyboard('usb', True, state['language']), keyboard('laptop', False, state['laptop'])]}
else:
    result = dict(state)
    if args[0] == 'select':
        if args[1] == 'vi': time.sleep(.25)
        result['language'] = result['laptop'] = args[1]
        if args[1] != 'en':
            result['secondary'] = args[1]
        result['running'] = result['secondary'] == 'vi'
        path.write_text(json.dumps(result))
    elif len(args) > 1 and args[1] == 'laptop' and state['secondary'] == 'bg':
        result['language'] = state['laptop']
# Read before delaying: reproduce an event arriving during an old status read.
if args[0] in ('status', '-j'):
    time.sleep(.35)
print(json.dumps(result))
PY
chmod +x "$language_test_root/bin/language-tool"
for tool in input-controller-fixture hyprctl language-fixture; do
    ln -s language-tool "$language_test_root/bin/$tool"
done
cat > "$language_test_root/config/zephyrus-shell/input-language.json" <<'JSON'
{"command":["input-controller-fixture"]}
JSON
# Restrict PATH so fixtures never contact host tools.
for tool in bash timeout quickshell python3 dbus-run-session dbus-daemon cat rg rm; do
    ln -s "$(command -v "$tool")" "$language_test_root/bin/$tool"
done
export PATH="$language_test_root/bin"
export XDG_CONFIG_HOME="$language_test_root/config" XDG_RUNTIME_DIR="$language_test_root/runtime"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1
export NO_AT_BRIDGE=1
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
# Real button, popup and singleton. Only external tools are faked; no services
# or keyboard layouts in the user's desktop are changed.
run_smoke() {
    timeout 16s dbus-run-session quickshell -p "$PWD/language-smoke.qml" --no-color > "$language_test_root/log" 2>&1 || { cat "$language_test_root/log"; return 1; }
    cat "$language_test_root/log"
    rg -q 'LANGUAGE PASS' "$language_test_root/log"
    test -s tests/artifacts/language-button.png
    test -s tests/artifacts/language-menu.png
    if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR|LANGUAGE FAIL' "$language_test_root/log"; then return 1; fi
}
run_smoke
# A configured provider can report that Vietnamese is unavailable.
rm "$ZEPHYRUS_LANGUAGE_FIXTURE"
export ZEPHYRUS_LANGUAGE_READY=0 ZEPHYRUS_LANGUAGE_STANDALONE=1
run_smoke
# Repeat against the bundled fallback, without a configured provider.
rm "$language_test_root/config/zephyrus-shell/input-language.json" "$ZEPHYRUS_LANGUAGE_FIXTURE"
export ZEPHYRUS_LANGUAGE_STANDALONE=1
run_smoke
