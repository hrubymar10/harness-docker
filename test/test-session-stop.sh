#!/bin/bash
# A launcher that receives TERM, INT or HUP ends its session in the container
# before it exits. The mock `docker exec` runs the real session wrapper on this
# machine in its own session, as Docker does, and like Docker it never forwards
# a signal to it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); POINTER="$ROOT/config/.current-generation"; POINTER_BACKUP=""
ENV_FILE="$ROOT/config/.env"; ENV_BACKUP=""
restore() {
  local pid
  if [[ -n "$POINTER_BACKUP" ]]; then cp "$POINTER_BACKUP" "$POINTER"; else rm -f "$POINTER"; fi
  if [[ -n "$ENV_BACKUP" ]]; then mv "$ENV_BACKUP" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  for pid in $(cat "$TMP"/harness-*.pid 2>/dev/null); do kill -KILL "$pid" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap restore EXIT
if [[ -f "$POINTER" ]]; then POINTER_BACKUP="$TMP/current-generation.bak"; cp "$POINTER" "$POINTER_BACKUP"; fi
if [[ -f "$ENV_FILE" ]]; then ENV_BACKUP="$TMP/env.bak"; mv "$ENV_FILE" "$ENV_BACKUP"; fi
mkdir -p "$TMP/bin" "$TMP/session-bin" "$TMP/pids" "$TMP/work/project"; printf 'manual\n' > "$POINTER"
ln -s "$ROOT/scripts/harness-session.sh" "$TMP/session-bin/claude-session"

cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
case "$1" in
  info|compose) ;;
  ps) echo cid-pinned ;;
  inspect)
    case "$*" in
      *State.Status*) echo running ;;
      *Config.Env*) ;;
      *com.docker.compose.project*) echo harness-docker-gmanual ;;
      *) echo "$MOUNT" ;;
    esac
    ;;
  exec)
    shift; envs=()
    while (($#)); do
      case "$1" in
        -i|-t) shift ;;
        -e) [[ "$2" == *=* ]] && envs+=("$2"); shift 2 ;;
        -u|-w) shift 2 ;;
        *) break ;;
      esac
    done
    shift
    if [[ "$1" == *-session ]]; then
      if command -v setsid >/dev/null 2>&1; then lead=(setsid)
      else lead=(python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])'); fi
      # Docker starts the session even when its client is killed during the start.
      (sleep "${SESSION_START_DELAY:-0}"; exec env "${envs[@]}" "${lead[@]}" "$SESSION_BIN/$1" "${@:2}") <&0 &
      session=$!
      # Bash reports a killed job on stderr; the session's own stderr is kept.
      exec 2>/dev/null
      wait "$session"
      exit "$?"
    fi
    exec env "${envs[@]}" "$@"
    ;;
  *) exit 2 ;;
esac
EOF
# The harness echoes its input until EOF. With IGNORE_TERM=1 it outlives TERM.
# With HELPER_DONE set it starts a helper that needs half a second to finish on
# TERM and then creates that file.
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/bash
[[ "${1:-}" == daemon ]] && exit 0
[[ "${IGNORE_TERM:-0}" == 1 ]] && trap '' TERM
if [[ -n "${HELPER_DONE:-}" ]]; then
  bash -c 'trap "sleep 0.5; : > \"$1\"; exit 0" TERM; while :; do sleep 0.1; done' sh "$HELPER_DONE" &
fi
echo $$ > "$HARNESS_PID_FILE"
while IFS= read -r line; do echo "got $line"; done
EOF
chmod +x "$TMP/bin/docker" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH" MOUNT="$TMP/work" SESSION_BIN="$TMP/session-bin" HARNESS_DOCKER_SKIP_UPDATE_CHECK=1 \
  HARNESS_DOCKER_USER=tester HARNESS_DOCKER_SESSION_PID_DIR="$TMP/pids" HARNESS_DOCKER_SESSION_DEBUG_LOG="$TMP/debug.log"
unset SSH_AUTH_SOCK

# A zombie counts as gone: it runs nothing and only waits for its parent.
running() { local state; state=$(ps -o stat= -p "$1" 2>/dev/null) || return 1; [[ -n "$state" && "$state" != Z* ]]; }
wait_for() { local i; for ((i = 0; i < 100; i++)); do eval "$1" && return 0; sleep 0.1; done; echo "timed out waiting for: $1" >&2; return 1; }
session_pidfile() { set -- "$TMP"/pids/claude-session-*.pid; [[ -f "$1" ]] && printf '%s' "$1"; }

# Stdin EOF still ends a session normally, with the harness's output and status.
export HARNESS_PID_FILE="$TMP/harness-eof.pid"
out=$(cd "$TMP/work/project"; printf 'hello\n' | "$ROOT/bin/claude-docker")
[[ "$out" == 'got hello' ]]
[[ -z "$(session_pidfile)" ]]

for signal in TERM INT HUP; do
  for ignore_term in 0 1; do
    export HARNESS_PID_FILE="$TMP/harness-$signal-$ignore_term.pid" IGNORE_TERM="$ignore_term"
    rm -f "$TMP/in"; mkfifo "$TMP/in"; exec 4<>"$TMP/in"
    # Job control keeps INT deliverable: a plain background job starts with INT ignored.
    set -m
    (cd "$TMP/work/project"; exec "$ROOT/bin/claude-docker" < "$TMP/in" > "$TMP/out") &
    launcher=$!
    set +m
    wait_for '[[ -s "$HARNESS_PID_FILE" && -n "$(session_pidfile)" ]]'
    harness=$(cat "$HARNESS_PID_FILE"); wrapper=$(cat "$(session_pidfile)")
    running "$harness"; running "$wrapper"
    start=$SECONDS
    kill -"$signal" "$launcher"
    status=0; wait "$launcher" || status=$?
    # The launcher exits only after the session is gone, well before the watchdog's next heartbeat.
    [[ "$status" == $((128 + $(kill -l "$signal"))) ]] || { echo "$signal: launcher exited $status" >&2; exit 1; }
    if running "$harness" || running "$wrapper"; then echo "$signal: session outlived the launcher" >&2; exit 1; fi
    [[ -z "$(session_pidfile)" ]]
    ((SECONDS - start <= 6)) || { echo "$signal: stopping took $((SECONDS - start)) s" >&2; exit 1; }
    exec 4>&-
  done
done
grep -q 'stop_session_now .* result=stopped' "$TMP/debug.log"

# A signal that arrives while the session is still starting cancels it, however
# long the start takes: the session exits before it starts the harness.
export HARNESS_PID_FILE="$TMP/harness-starting.pid" IGNORE_TERM=0 SESSION_START_DELAY=3
: > "$TMP/debug.log"
rm -f "$TMP/in"; mkfifo "$TMP/in"; exec 4<>"$TMP/in"
(cd "$TMP/work/project"; exec "$ROOT/bin/claude-docker" < "$TMP/in" > "$TMP/out") &
launcher=$!
wait_for 'grep -q start_watchdog "$TMP/debug.log"'
kill -TERM "$launcher"
status=0; wait "$launcher" || status=$?
[[ "$status" == 143 ]]
grep -q 'stop_session_now .* result=cancelled_before_start' "$TMP/debug.log"
# Let the session come up after the launcher has exited.
sleep 3.5
[[ ! -e "$HARNESS_PID_FILE" ]] || { echo "a starting session ran its harness after the launcher exited" >&2; exit 1; }
[[ -z "$(session_pidfile)" ]]
set -- "$TMP"/pids/*.cancelled; [[ ! -e "$1" ]] || { echo "the cancel marker was left behind" >&2; exit 1; }
exec 4>&-
unset SESSION_START_DELAY

# Other processes of the session get their own time to finish on TERM, even
# when the harness exits at once.
export HARNESS_PID_FILE="$TMP/harness-helper.pid" HELPER_DONE="$TMP/helper-done"
rm -f "$TMP/in"; mkfifo "$TMP/in"; exec 4<>"$TMP/in"
set -m
(cd "$TMP/work/project"; exec "$ROOT/bin/claude-docker" < "$TMP/in" > "$TMP/out") &
launcher=$!
set +m
wait_for '[[ -s "$HARNESS_PID_FILE" && -n "$(session_pidfile)" ]]'
kill -TERM "$launcher"
status=0; wait "$launcher" || status=$?
[[ "$status" == 143 ]]
[[ -e "$HELPER_DONE" ]] || { echo "a helper of the session was killed before it finished" >&2; exit 1; }
exec 4>&-
unset HELPER_DONE

# The probe tells a supervisor that this launcher stops its session on a signal.
HARNESS_DOCKER_PRINT_FEATURES=1 "$ROOT/bin/codex-docker" --version | grep -qx stop_on_signal
echo "session stop tests passed"
