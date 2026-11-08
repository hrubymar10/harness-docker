#!/bin/sh
# Wrapper that keeps a supervising shell alive around a coding-agent harness
# so host-side cleanup can always deliver SIGHUP to a process group owned
# inside the container, including non-TTY callers such as automation/IDE wrappers.

SESSION_COMMAND=$(basename "$0")
HARNESS=${SESSION_COMMAND%-session}

case "$HARNESS" in
    claude|codex|pi|vibe|opencode) ;;
    *)
        echo "Unsupported session command: $SESSION_COMMAND" >&2
        exit 64
        ;;
esac

SESSION_VAR=$(printf '%s_SESSION_ID' "$HARNESS" | tr '[:lower:]' '[:upper:]')
eval "SESSION_ID=\${$SESSION_VAR:-}"

PID_FILE=""
if [ -n "$SESSION_ID" ]; then
    SESSION_PID_DIR=${HARNESS_DOCKER_SESSION_PID_DIR:-/tmp}
    case "$SESSION_PID_DIR" in /*) ;; *) echo "HARNESS_DOCKER_SESSION_PID_DIR must be absolute" >&2; exit 64 ;; esac
    mkdir -p "$SESSION_PID_DIR"
    PID_FILE="$SESSION_PID_DIR/$HARNESS-session-${SESSION_ID}.pid"
    echo $$ > "$PID_FILE"
    # A launcher that was stopped before this session started leaves this
    # marker. It writes the marker before it looks for the pidfile written above,
    # so either it finds that pidfile or this check finds its marker.
    CANCEL_FILE="$SESSION_PID_DIR/$HARNESS-session-${SESSION_ID}.cancelled"
    if [ -e "$CANCEL_FILE" ]; then
        rm -f "$PID_FILE" "$CANCEL_FILE"
        exit 143
    fi
fi

HARNESS_PID=""

# True while a process other than this shell is left in its process group,
# which `docker exec` made its own. A zombie no longer runs anything. Called
# from cleanup only.
# shellcheck disable=SC2329
session_running() {
    # Without /proc (a test on a macOS host), only the harness is checked.
    [ -d /proc/self ] || { [ -n "$HARNESS_PID" ] && kill -0 "$HARNESS_PID" 2>/dev/null; return; }
    for stat in /proc/[0-9]*/stat; do
        [ "$stat" = "/proc/$$/stat" ] && continue
        read -r line 2>/dev/null < "$stat" || continue
        # After the command name: state, parent, process group.
        # shellcheck disable=SC2086
        set -- ${line##*) }
        [ "$3" = "$$" ] && [ "$1" != Z ] && return 0
    done
    return 1
}

# Invoked indirectly by the traps below. The session's processes get up to 2
# seconds to exit on TERM; a stopping launcher waits for this shell, so it
# should not wait longer than they need.
# shellcheck disable=SC2329
cleanup() {
    trap '' HUP TERM INT EXIT
    [ -n "$PID_FILE" ] && rm -f "$PID_FILE"
    kill -TERM 0 2>/dev/null
    ticks=20
    while [ "$ticks" -gt 0 ] && session_running; do
        sleep 0.1
        ticks=$((ticks - 1))
    done
    kill -KILL 0 2>/dev/null
}

trap cleanup HUP TERM INT EXIT

# Duplicate stdin before backgrounding so non-interactive callers keep a live
# input stream while this shell remains resident for signal handling.
exec 3<&0
"$HARNESS" "$@" <&3 &
HARNESS_PID=$!
wait "$HARNESS_PID" 2>/dev/null
EXIT_CODE=$?

trap - HUP TERM INT EXIT
exec 3<&-
[ -n "$PID_FILE" ] && rm -f "$PID_FILE"
exit "$EXIT_CODE"
