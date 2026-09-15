#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); POINTER="$ROOT/config/.current-generation"; POINTER_BACKUP=""
ENV_FILE="$ROOT/config/.env"; ENV_BACKUP=""
restore() {
  if [[ -n "$POINTER_BACKUP" ]]; then cp "$POINTER_BACKUP" "$POINTER"; else rm -f "$POINTER"; fi
  if [[ -n "$ENV_BACKUP" ]]; then mv "$ENV_BACKUP" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
  ps -eo pid=,command= 2>/dev/null | awk -v mock="$TMP/bin/socat" '$3 == mock {print $1}' | xargs kill 2>/dev/null || true
  rm -rf "$TMP"
}
trap restore EXIT
if [[ -f "$POINTER" ]]; then POINTER_BACKUP="$TMP/current-generation.bak"; cp "$POINTER" "$POINTER_BACKUP"; fi
if [[ -f "$ENV_FILE" ]]; then ENV_BACKUP="$TMP/env.bak"; mv "$ENV_FILE" "$ENV_BACKUP"; fi
mkdir -p "$TMP/bin" "$TMP/work/project"; printf 'manual\n' > "$POINTER"
cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
printf '%q ' "$@" >> "$LOG"; printf '\n' >> "$LOG"
case "$1" in
  info) ;;
  ps) [[ "$*" == *'service=harness'* ]] && echo cid-pinned ;;
  inspect)
    case "$*" in
      *State.Status*) echo running ;;
      *Config.Env*) [[ -z "${MOCK_RELAY_PORT:-}" ]] || printf 'SSH_RELAY_HOST=host.docker.internal\nSSH_RELAY_PORT=%s\n' "$MOCK_RELAY_PORT" ;;
      *) echo "$MOUNT" ;;
    esac
    ;;
  exec)
    if [[ "$*" == *'echo "$#"'* ]]; then echo 0
    elif [[ "$*" == *-session* && "$*" != *'sh -c'* ]]; then echo harness-mock
    fi
    ;;
  compose) ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH" LOG="$TMP/log" MOUNT="$TMP/work" HARNESS_DOCKER_SKIP_UPDATE_CHECK=1 HARNESS_DOCKER_USER=tester
unset SSH_AUTH_SOCK
# shellcheck disable=SC1091
source "$ROOT/bin/lib/harness.sh"
for harness in claude codex pi vibe opencode; do
  case "$harness" in
    claude) expected_env=CLAUDE_SESSION_ID; expected_wrapper=claude-session; expected_flags='--dangerously-skip-permissions' ;;
    codex) expected_env=CODEX_SESSION_ID; expected_wrapper=codex-session; expected_flags='--dangerously-bypass-approvals-and-sandbox' ;;
    pi) expected_env=PI_SESSION_ID; expected_wrapper=pi-session; expected_flags='' ;;
    vibe) expected_env=VIBE_SESSION_ID; expected_wrapper=vibe-session; expected_flags='--yolo' ;;
    opencode) expected_env=OPENCODE_SESSION_ID; expected_wrapper=opencode-session; expected_flags='--auto' ;;
  esac
  : > "$LOG"
  (cd "$TMP/work/project"; "$ROOT/bin/$harness-docker" --version > "$TMP/out")
  load_harness_spec "$harness"
  [[ "$HARNESS_SESSION_ENV" == "$expected_env" && "$HARNESS_SESSION_WRAPPER" == "$expected_wrapper" ]]
  [[ "${HARNESS_LAUNCH_FLAGS[*]-}" == "$expected_flags" ]]
  [[ "${#HARNESS_STATE_DIR_ENVS[@]}" == "${#HARNESS_STATE_DIR_SUFFIXES[@]}" ]]
  if [[ "$harness" == opencode ]]; then
    [[ "${HARNESS_STATE_DIR_ENVS[*]}" == 'OPENCODE_CONFIG_DIR XDG_DATA_HOME' ]]
    [[ "${HARNESS_STATE_DIR_SUFFIXES[*]}" == ' opencode' ]]
  fi
  [[ "$(HARNESS_DOCKER_ROOT="$ROOT" bash -c 'source "$HARNESS_DOCKER_ROOT/bin/lib/harness.sh"; harness_from_launcher "$0"' "$ROOT/bin/$harness-docker")" == "$harness" ]]
  grep -q '^harness-mock$' "$TMP/out"
  grep -Eq "exec -i .*${HARNESS_SESSION_ENV}=.* -e HARNESS_DOCKER_SESSION_PID_DIR=/tmp -u tester -w .*/work/project cid-pinned ${HARNESS_SESSION_WRAPPER}" "$LOG"
  for flag in ${HARNESS_LAUNCH_FLAGS[@]+"${HARNESS_LAUNCH_FLAGS[@]}"}; do grep -Fq -- "$flag" "$LOG"; done
done

: > "$LOG"
(cd "$TMP/work/project"; CLAUDE_LAUNCH_FLAGS='--permission-mode auto --settings /etc/claude/hooks.json' "$ROOT/bin/claude-docker" --version >/dev/null)
grep -q 'cid-pinned claude-session --permission-mode auto --settings /etc/claude/hooks.json --version' "$LOG"
if grep -q -- '--dangerously-skip-permissions' "$LOG"; then exit 1; fi
: > "$LOG"
(cd "$TMP/work/project"; VIBE_LAUNCH_FLAGS='' "$ROOT/bin/vibe-docker" --version >/dev/null)
grep -q 'cid-pinned vibe-session --version' "$LOG"
printf 'OPENCODE_LAUNCH_FLAGS="--auto --model example/quoted"\n' > "$ENV_FILE"
: > "$LOG"
(cd "$TMP/work/project"; "$ROOT/bin/opencode-docker" --version >/dev/null)
grep -q 'cid-pinned opencode-session --auto --model example/quoted --version' "$LOG"
printf 'VIBE_LAUNCH_FLAGS=--yolo\n' > "$ENV_FILE"
: > "$LOG"
(cd "$TMP/work/project"; VIBE_LAUNCH_FLAGS='' "$ROOT/bin/vibe-docker" --version >/dev/null)
grep -q 'cid-pinned vibe-session --version' "$LOG"
if grep -q -- '--yolo' "$LOG"; then exit 1; fi
rm -f "$ENV_FILE"

# SSH relay heal: the launcher restores the relay with the port the container
# was started with, detached from its own stdio, without duplicating a relay
# that another caller holds.
# The mock holds a per-port lock so a second listener fails like a real bind.
cat > "$TMP/bin/socat" <<'EOF'
#!/bin/bash
port="${1#TCP-LISTEN:}"; port="${port%%,*}"; lock="$SOCAT_LOCK_DIR/$port"
mkdir "$lock" 2>/dev/null || { echo 'E bind: Address already in use' >&2; exit 1; }
release() { kill "$sleeper" 2>/dev/null; rmdir "$lock" 2>/dev/null; exit 0; }
printf '%s\n' "$*" >> "$SOCAT_LOG"; sleep 60 & sleeper=$!; trap release TERM; wait "$sleeper"
EOF
cat > "$TMP/bin/lsof" <<'EOF'
#!/bin/bash
[[ "${LSOF_PORT_SERVED:-0}" == 1 ]]
EOF
chmod +x "$TMP/bin/socat" "$TMP/bin/lsof"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$TMP/agent.sock"
export SOCAT_LOG="$TMP/socat.log" SOCAT_LOCK_DIR="$TMP/socat-locks" MOCK_RELAY_PORT=19922; : > "$SOCAT_LOG"; mkdir -p "$SOCAT_LOCK_DIR"
relay_home="$TMP/relay-home"; mkdir -p "$relay_home"; PID_FILE="$relay_home/.harness-docker-ssh-relay.pid"
AGENT_SOCK="$TMP/agent.sock"
socat_lines() { wc -l < "$SOCAT_LOG" | tr -d ' '; }
wait_for() { local i; for ((i = 0; i < 50; i++)); do eval "$1" && return 0; sleep 0.1; done; echo "timed out waiting for: $1" >&2; return 1; }
launch() { (cd "$TMP/work/project"; HOME="$relay_home" SSH_AUTH_SOCK="$AGENT_SOCK" "$ROOT/bin/pi-docker" --version); }
relay_line() { printf 'TCP-LISTEN:%s,fork,reuseaddr,bind=127.0.0.1 UNIX-CONNECT:%s' "$1" "$2"; }

(cd "$TMP/work/project"; env -u SSH_AUTH_SOCK HOME="$relay_home" "$ROOT/bin/pi-docker" --version >/dev/null)
[[ ! -s "$SOCAT_LOG" && ! -f "$PID_FILE" ]]
MOCK_RELAY_PORT= launch >/dev/null
[[ ! -s "$SOCAT_LOG" && ! -f "$PID_FILE" ]]

# First heal: the piped launcher must still deliver EOF once the session ends.
( launch | cat > "$TMP/pipe.out" ) & pipe_pid=$!
wait_for '! kill -0 "$pipe_pid" 2>/dev/null' || { kill "$pipe_pid" 2>/dev/null; echo 'relay kept the launcher stdout open' >&2; exit 1; }
grep -q '^harness-mock$' "$TMP/pipe.out"
wait_for '[[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
wait_for '[[ "$(socat_lines)" == 1 ]]'
grep -Fxq "$(relay_line 19922 "$AGENT_SOCK")" "$SOCAT_LOG"
relay_pid=$(cat "$PID_FILE")

launch >/dev/null; sleep 0.3
[[ "$(socat_lines)" == 1 && "$(cat "$PID_FILE")" == "$relay_pid" ]]

kill "$relay_pid"; wait_for '! kill -0 "$relay_pid" 2>/dev/null'
launch >/dev/null
wait_for '[[ "$(socat_lines)" == 2 ]]'
wait_for '[[ -f "$PID_FILE" ]] && [[ "$(cat "$PID_FILE")" != "$relay_pid" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
relay_pid=$(cat "$PID_FILE")

# The agent socket moved: the relay forwarding to the old path is replaced.
rm -f "$AGENT_SOCK"; AGENT_SOCK="$TMP/agent2.sock"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$AGENT_SOCK"
launch >/dev/null
wait_for '! kill -0 "$relay_pid" 2>/dev/null'
wait_for '[[ "$(socat_lines)" == 3 ]]'
grep -Fxq "$(relay_line 19922 "$AGENT_SOCK")" "$SOCAT_LOG"
wait_for '[[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
relay_pid=$(cat "$PID_FILE")

# The agent crashed without unlinking its socket, then restarted at a new path.
stale_agent_sock="$AGENT_SOCK"; AGENT_SOCK="$TMP/agent3.sock"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$AGENT_SOCK"
[[ -S "$stale_agent_sock" ]]
launch >/dev/null
wait_for '! kill -0 "$relay_pid" 2>/dev/null'
wait_for '[[ "$(socat_lines)" == 4 ]]'
grep -Fxq "$(relay_line 19922 "$AGENT_SOCK")" "$SOCAT_LOG"
wait_for '[[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
relay_pid=$(cat "$PID_FILE")

# Launchers racing on a dead relay: only the spawn that holds the port records itself.
kill "$relay_pid"; wait_for '! kill -0 "$relay_pid" 2>/dev/null'
launch >/dev/null & first=$!; launch >/dev/null & second=$!; wait "$first" "$second"
wait_for '[[ "$(socat_lines)" == 5 ]]'
wait_for '[[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
sleep 0.5; [[ "$(socat_lines)" == 5 ]]
relay_pid=$(cat "$PID_FILE")
live_relays=$(ps -eo pid=,command= | awk -v mock="$TMP/bin/socat" '$3 == mock {print $1}')
[[ "$live_relays" == "$relay_pid" ]]
if compgen -G "$PID_FILE.*" >/dev/null; then exit 1; fi

# A port served by another process is reused, quietly, and never recorded.
kill "$relay_pid"; wait_for '! kill -0 "$relay_pid" 2>/dev/null'; rm -f "$PID_FILE"
LSOF_PORT_SERVED=1 launch > "$TMP/reuse.out" 2>&1; sleep 0.3
if grep -q 'already served' "$TMP/reuse.out"; then exit 1; fi
[[ "$(socat_lines)" == 5 && ! -f "$PID_FILE" ]]

# The launcher heals on the port the container was started with.
MOCK_RELAY_PORT=20000 launch >/dev/null
wait_for '[[ "$(socat_lines)" == 6 ]]'
grep -Fxq "$(relay_line 20000 "$AGENT_SOCK")" "$SOCAT_LOG"
wait_for '[[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null'
relay_pid=$(cat "$PID_FILE")

# stop_ssh_relay stops the recorded relay only.
HOME="$relay_home" bash -c 'source "$1/bin/lib/ssh-relay.sh"; stop_ssh_relay' sh "$ROOT"
wait_for '! kill -0 "$relay_pid" 2>/dev/null'
[[ ! -f "$PID_FILE" ]]
unset SOCAT_LOG SOCAT_LOCK_DIR MOCK_RELAY_PORT

MOUNT="$TMP/elsewhere"
if (cd "$TMP/work/project"; "$ROOT/bin/codex-docker" --version > "$TMP/reject.out" 2>&1); then exit 1; fi
grep -Fq 'is not mounted' "$TMP/reject.out"
MOUNT="$TMP/work"

cat > "$TMP/pty_run.py" <<'PY'
import os,pty,sys
raise SystemExit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))
PY
: > "$LOG"
(cd "$TMP/work/project"; printf '' | python3 "$TMP/pty_run.py" "$ROOT/bin/codex-docker" --version >/dev/null)
grep -q 'exec -i -t ' "$LOG"
grep -q 'cid-pinned codex-session' "$LOG"
echo 'shared launchers: ok'
