#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/harness-blue-green.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/mock-bin" "$TEST_ROOT/sessions"
touch "$TEST_ROOT/docker-compose.yml" "$TEST_ROOT/containers" "$TEST_ROOT/down-calls"

cat > "$TEST_ROOT/mock-bin/docker" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$1" in
  ps)
    project=""
    [[ "$*" =~ com.docker.compose.project=([^[:space:]]+) ]] && project="${BASH_REMATCH[1]}"
    if [[ -n "$project" ]]; then
      awk -F'|' -v project="$project" '$1 == project {print $2}' "$MOCK_CONTAINERS"
    else
      awk -F'|' '{print $1}' "$MOCK_CONTAINERS"
    fi
    ;;
  inspect)
    container="${*: -1}"
    awk -F'|' -v container="$container" '$2 == container {print $1}' "$MOCK_CONTAINERS"
    ;;
  exec)
    shift
    while [[ "${1:-}" == -* ]]; do
      [[ "$1" == -u ]] && shift
      shift
    done
    container="$1"; shift
    if [[ "$*" == *'kill -HUP'* ]]; then
      pidfile="${*: -1}"
      rm -f "$MOCK_SESSIONS/$container/$(basename "$pidfile")"
      echo pidfile_found
    fi
    ;;
  compose)
    project=""
    while (($#)); do
      if [[ "$1" == -p ]]; then project="$2"; shift 2
      elif [[ "$1" == down ]]; then break
      else shift
      fi
    done
    echo "$project" >> "$MOCK_DOWN_CALLS"
    awk -F'|' -v project="$project" '$1 != project' "$MOCK_CONTAINERS" > "$MOCK_CONTAINERS.new"
    mv "$MOCK_CONTAINERS.new" "$MOCK_CONTAINERS"
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$TEST_ROOT/mock-bin/docker"

export PATH="$TEST_ROOT/mock-bin:$PATH"
export MOCK_CONTAINERS="$TEST_ROOT/containers"
export MOCK_DOWN_CALLS="$TEST_ROOT/down-calls"
export MOCK_SESSIONS="$TEST_ROOT/sessions"
export HARNESS_DOCKER_ROOT="$TEST_ROOT"
export HARNESS_DOCKER_SESSION_PID_DIR="$TEST_ROOT/session-pids"
export HARNESS_COMPOSE_PROJECT_NAME=harness-docker

# shellcheck disable=SC1091
source "$ROOT/bin/lib/generations.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/lib/session-cleanup.sh"

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "assertion failed: got '$1', want '$2'" >&2; exit 1; }
}

down_count() {
  wc -l < "$MOCK_DOWN_CALLS" | tr -d ' '
}

heartbeat_mtime() {
  _heartbeat_mtime "$1"
}

# A launcher pins a container, and its generation comes from that container's
# immutable Compose label rather than the mutable current pointer.
printf '%s\n' 'harness-docker-gold|container-old' > "$MOCK_CONTAINERS"
mkdir -p "$MOCK_SESSIONS/container-old" "$MOCK_SESSIONS/container-new"
write_current_generation old
pinned=$(current_agent_container_id)
assert_eq "$(container_generation "$pinned")" old
write_current_generation new
assert_eq "$pinned" container-old

# The current pointer is protected even before its first session heartbeat.
write_current_generation old
reap_retired_generations
assert_eq "$(down_count)" 0

# A discovered non-current generation with no heartbeat is reaped without a
# retirement marker.
printf '%s\n' 'harness-docker-gold|container-old' 'harness-docker-gnew|container-new' > "$MOCK_CONTAINERS"
write_current_generation new
reap_retired_generations
assert_eq "$(down_count)" 1
assert_eq "$(tail -n 1 "$MOCK_DOWN_CALLS")" harness-docker-gold

# A fresh heartbeat protects a non-current generation and counts as one live
# session. Once stale, that same generation is reaped and its directory pruned.
printf '%s\n' 'harness-docker-gold|container-old' >> "$MOCK_CONTAINERS"
mkdir -p "$TEST_ROOT/config/.generations/old"
touch "$TEST_ROOT/config/.generations/old/live.hb"
assert_eq "$(generation_session_count old)" 1
heartbeat_age=$(generation_last_heartbeat_age old)
((heartbeat_age < _SESSION_HEARTBEAT_STALE_AFTER_SECONDS))
reap_retired_generations
assert_eq "$(down_count)" 1
touch -t 200001010000 "$TEST_ROOT/config/.generations/old/live.hb"
assert_eq "$(generation_session_count old)" 0
reap_retired_generations
assert_eq "$(down_count)" 2
[[ ! -d "$TEST_ROOT/config/.generations/old" ]]

# Reaping is idempotent after Compose no longer reports the generation.
reap_retired_generations
reap_retired_generations
assert_eq "$(down_count)" 2

# Normal cleanup removes its fresh heartbeat before reaping, so a session that
# exits cleanly never protects an abandoned generation for the stale timeout.
printf '%s\n' 'harness-docker-gold|container-old' >> "$MOCK_CONTAINERS"
mkdir -p "$TEST_ROOT/config/.generations/old"
touch "$TEST_ROOT/config/.generations/old/clean.hb"
touch "$MOCK_SESSIONS/container-old/claude-session-clean.pid"
export HARNESS=claude
before_clean_exit=$(down_count)
run_session_cleanup container-old clean old test-user
[[ ! -f "$TEST_ROOT/config/.generations/old/clean.hb" ]]
assert_eq "$(down_count)" "$((before_clean_exit + 1))"

# The watchdog creates a heartbeat before detaching, refreshes it on cadence
# only while the exact parent identity lives, then removes it before reaping.
printf '%s\n' 'harness-docker-gold|container-old' >> "$MOCK_CONTAINERS"
touch "$MOCK_SESSIONS/container-old/claude-session-wd-sess.pid"
_spawn_detached() { WD_SCRIPT="$1"; shift; WD_ARGS=("$@"); }
_SESSION_HEARTBEAT_INTERVAL_SECONDS=0.1
sleep 60 & wd_parent=$!
start_session_watchdog container-old wd-sess "$wd_parent" old test-user
heartbeat="$TEST_ROOT/config/.generations/old/wd-sess.hb"
[[ -f "$heartbeat" ]]
initial_mtime=$(heartbeat_mtime "$heartbeat")
bash -c "$WD_SCRIPT" sh "${WD_ARGS[@]}" >/dev/null 2>&1 & watchdog_runner=$!
sleep 1.1
refreshed_mtime=$(heartbeat_mtime "$heartbeat")
((refreshed_mtime > initial_mtime))
before_clean_exit=$(down_count)
kill "$wd_parent" 2>/dev/null || true
wait "$wd_parent" 2>/dev/null || true
wait "$watchdog_runner"
[[ ! -f "$heartbeat" ]]
assert_eq "$(down_count)" "$((before_clean_exit + 1))"
assert_eq "$(tail -n 1 "$MOCK_DOWN_CALLS")" harness-docker-gold

echo 'blue-green generation guarantees: ok'
