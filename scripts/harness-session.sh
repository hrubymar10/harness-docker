#!/bin/sh
# Wrapper that keeps a supervising shell alive around a coding-agent harness
# so host-side cleanup can always deliver SIGHUP to a process group owned
# inside the container, including non-TTY callers such as aimebu/IDE wrappers.

SESSION_COMMAND=$(basename "$0")
HARNESS=${SESSION_COMMAND%-session}

case "$HARNESS" in
    claude|codex|pi|vibe) ;;
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
fi

# Invoked indirectly by the traps below.
# shellcheck disable=SC2329
cleanup() {
    trap '' HUP TERM INT EXIT
    [ -n "$PID_FILE" ] && rm -f "$PID_FILE"
    kill -TERM 0 2>/dev/null
    sleep 2
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
