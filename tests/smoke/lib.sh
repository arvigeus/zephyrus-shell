# Shared setup for offscreen smoke checks; source it from tests/smoke/<name>.sh.
# Every check gets private XDG directories, the offscreen Qt platform, no access
# to the running Hyprland session, and a private D-Bus session per harness.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[1]}")/../.."
export SMOKE_ROOT
SMOKE_ROOT=$(mktemp -d)
smoke_cleanup=()
# on_exit <command>: run a command on exit, before the temporary root is removed.
on_exit() { smoke_cleanup+=("$1"); }
_smoke_exit() {
    local command
    for command in "${smoke_cleanup[@]}"; do eval "$command" || true; done
    rm -rf -- "$SMOKE_ROOT"
}
trap _smoke_exit EXIT
export XDG_CONFIG_HOME="$SMOKE_ROOT/config" XDG_DATA_HOME="$SMOKE_ROOT/data"
export XDG_CACHE_HOME="$SMOKE_ROOT/cache" XDG_STATE_HOME="$SMOKE_ROOT/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts

# offline: route public HTTP(S) to a closed port; local fixtures stay reachable.
offline() {
    export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
    unset ALL_PROXY all_proxy
    export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
}

# start_fixture <name> <command...>: run a fixture until exit, logging to <name>.log.
start_fixture() {
    local name=$1
    shift
    "$@" >"$SMOKE_ROOT/$name.log" 2>&1 &
    on_exit "kill $! 2>/dev/null; wait $! 2>/dev/null"
}

# wait_for <path>: wait up to five seconds for a fixture to create a file.
wait_for() {
    local attempt
    for attempt in {1..50}; do
        [[ -e $1 ]] && return 0
        sleep 0.1
    done
    printf 'smoke: timed out waiting for %s\n' "$1" >&2
    cat "$SMOKE_ROOT"/*.log >&2 || true
    return 1
}

SMOKE_ERRORS='ReferenceError|TypeError|Cannot assign|Binding loop|Unable to assign|ERROR qml:|Cannot open:|Traceback'

# check_log <log> <marker> [extra-error-pattern]
# Passes when the log contains "<marker> PASS" and no QML or Python error.
check_log() {
    local log=$1 marker=$2 extra=${3:-}
    cat "$log"
    if ! rg -q "$marker PASS" "$log"; then
        printf 'smoke: missing "%s PASS"\n' "$marker" >&2
        return 1
    fi
    if rg "$SMOKE_ERRORS|$marker FAIL${extra:+|$extra}" "$log" >&2; then
        printf 'smoke: %s logged errors\n' "$marker" >&2
        return 1
    fi
}

# run_smoke <harness> <marker> [timeout] [extra-error-pattern]
# Runs tests/smoke/<harness>.qml in a private D-Bus session and checks its log.
run_smoke() {
    local harness=$1 marker=$2 limit=${3:-20s} extra=${4:-}
    local log="$SMOKE_ROOT/$harness.log"
    if ! ZEPHYRUS_HARNESS="tests/smoke/$harness.qml" timeout "$limit" \
        dbus-run-session quickshell -p "$PWD/harness.qml" --no-color >"$log" 2>&1; then
        cat "$log"
        return 1
    fi
    check_log "$log" "$marker" "$extra"
}
