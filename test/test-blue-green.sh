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
  exec)
    shift
    while [[ "${1:-}" == -* ]]; do
      [[ "$1" == -u ]] && shift
      shift
    done
    container="$1"; shift
    if [[ "$*" == *'echo "$#"'* ]]; then
      shopt -s nullglob
      files=("$MOCK_SESSIONS/$container"/*-session-*.pid)
      echo "${#files[@]}"
    elif [[ "$*" == *'kill -HUP'* ]]; then
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

printf '%s\n' 'harness-docker-gold|container-old' 'harness-docker-gnew|container-new' > "$MOCK_CONTAINERS"
mkdir -p "$MOCK_SESSIONS/container-old" "$MOCK_SESSIONS/container-new"

write_current_generation old
touch "$MOCK_SESSIONS/container-old/claude-session-pinned.pid"
pinned=$(current_agent_container_id)
write_current_generation new
assert_eq "$pinned" container-old
assert_eq "$(current_agent_container_id)" container-new
rm -f "$MOCK_SESSIONS/container-old/claude-session-pinned.pid"

mark_generation_retired old
reap_retired_generations
assert_eq "$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')" 1
assert_eq "$(tail -n 1 "$MOCK_DOWN_CALLS")" harness-docker-gold
[[ ! -f "$TEST_ROOT/config/.retired-generations/old" ]]

printf '%s\n' 'harness-docker-gold|container-old' >> "$MOCK_CONTAINERS"
touch "$MOCK_SESSIONS/container-old/claude-session-last.pid"
mark_generation_retired old
reap_retired_generations
assert_eq "$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')" 1
[[ -f "$TEST_ROOT/config/.retired-generations/old" ]]

export HARNESS=claude
run_session_cleanup container-old last test-user
assert_eq "$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')" 2
assert_eq "$(tail -n 1 "$MOCK_DOWN_CALLS")" harness-docker-gold
[[ ! -f "$TEST_ROOT/config/.retired-generations/old" ]]

reap_retired_generations
reap_retired_generations
assert_eq "$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')" 2

# --- watchdog cleanup path also reaps a retired, idle generation ---
printf '%s\n' 'harness-docker-gold|container-old' >> "$MOCK_CONTAINERS"
mark_generation_retired old
wd_before=$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')
_spawn_detached() { WD_SCRIPT="$1"; shift; WD_ARGS=("$@"); }
export HARNESS=claude
sleep 60 & wd_parent=$!
start_session_watchdog container-old wd-sess "$wd_parent" test-user
kill "$wd_parent" 2>/dev/null || true
wait "$wd_parent" 2>/dev/null || true
bash -c "$WD_SCRIPT" sh "${WD_ARGS[@]}" >/dev/null 2>&1 || true
assert_eq "$(wc -l < "$MOCK_DOWN_CALLS" | tr -d ' ')" "$((wd_before + 1))"
assert_eq "$(tail -n 1 "$MOCK_DOWN_CALLS")" harness-docker-gold
[[ ! -f "$TEST_ROOT/config/.retired-generations/old" ]]

echo 'blue-green generation guarantees: ok'
