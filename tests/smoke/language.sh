#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$SMOKE_ROOT/bin" "$SMOKE_ROOT/runtime"
export ZEPHYRUS_LANGUAGE_FIXTURE="$SMOKE_ROOT/state.json"
cat > "$SMOKE_ROOT/bin/language-tool" <<'PY'
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
chmod +x "$SMOKE_ROOT/bin/language-tool"
for tool in input-controller-fixture hyprctl language-fixture; do
    ln -s language-tool "$SMOKE_ROOT/bin/$tool"
done
cat > "$SMOKE_ROOT/config/zephyrus-shell/input-language.json" <<'JSON'
{"command":["input-controller-fixture"]}
JSON
# Restrict PATH so fixtures never contact host tools.
for tool in bash timeout quickshell python3 dbus-run-session dbus-daemon cat rg rm; do
    ln -s "$(command -v "$tool")" "$SMOKE_ROOT/bin/$tool"
done
export PATH="$SMOKE_ROOT/bin"
export XDG_RUNTIME_DIR="$SMOKE_ROOT/runtime" QT_NO_XDG_DESKTOP_PORTAL=1 NO_AT_BRIDGE=1
# Real button, popup and singleton. Only external tools are faked; no services
# or keyboard layouts in the user's desktop are changed.
check_language() {
    run_smoke language "LANGUAGE" 16s "ERROR"
    test -s tests/artifacts/language-button.png
    test -s tests/artifacts/language-menu.png
}
check_language
# A configured provider can report that Vietnamese is unavailable.
rm "$ZEPHYRUS_LANGUAGE_FIXTURE"
export ZEPHYRUS_LANGUAGE_READY=0 ZEPHYRUS_LANGUAGE_STANDALONE=1
check_language
# Repeat against the bundled fallback, without a configured provider.
rm "$SMOKE_ROOT/config/zephyrus-shell/input-language.json" "$ZEPHYRUS_LANGUAGE_FIXTURE"
export ZEPHYRUS_LANGUAGE_STANDALONE=1
check_language
