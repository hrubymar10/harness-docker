# shellcheck shell=bash

if [[ -z "${HARNESS_DOCKER_ROOT:-}" ]]; then
  HARNESS_DOCKER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

_GENERATION_POINTER="$HARNESS_DOCKER_ROOT/config/.current-generation"
_GENERATIONS_DIR="$HARNESS_DOCKER_ROOT/config/.generations"
_SESSION_HEARTBEAT_INTERVAL_SECONDS=15
_SESSION_HEARTBEAT_STALE_AFTER_SECONDS=60

_valid_generation() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

generation_project_name() {
  local generation="$1"
  _valid_generation "$generation" || return 1
  printf '%s-g%s' "${HARNESS_COMPOSE_PROJECT_NAME:-harness-docker}" "$generation"
}

read_current_generation() {
  local generation
  [[ -f "$_GENERATION_POINTER" ]] || return 1
  IFS= read -r generation < "$_GENERATION_POINTER"
  _valid_generation "$generation" || return 1
  printf '%s' "$generation"
}

write_current_generation() {
  local generation="$1" tmp
  _valid_generation "$generation" || return 1
  mkdir -p "$(dirname "$_GENERATION_POINTER")"
  tmp=$(mktemp "${_GENERATION_POINTER}.tmp.XXXXXX")
  if ! printf '%s\n' "$generation" > "$tmp" || ! mv -f "$tmp" "$_GENERATION_POINTER"; then
    rm -f "$tmp"
    return 1
  fi
}

clear_current_generation() {
  rm -f "$_GENERATION_POINTER"
}

generation_session_count() {
  local generation="$1" heartbeat count=0 now mtime age
  _valid_generation "$generation" || return 1
  now=$(date +%s)
  for heartbeat in "$_GENERATIONS_DIR/$generation"/*.hb; do
    [[ -f "$heartbeat" ]] || continue
    mtime=$(_heartbeat_mtime "$heartbeat") || continue
    age=$((now - mtime))
    ((age < _SESSION_HEARTBEAT_STALE_AFTER_SECONDS)) && ((count++)) || true
  done
  printf '%s' "$count"
}

generation_last_heartbeat_age() {
  local generation="$1" heartbeat now mtime newest="" age
  _valid_generation "$generation" || return 1
  now=$(date +%s)
  for heartbeat in "$_GENERATIONS_DIR/$generation"/*.hb; do
    [[ -f "$heartbeat" ]] || continue
    mtime=$(_heartbeat_mtime "$heartbeat") || continue
    [[ -n "$newest" && "$mtime" -le "$newest" ]] || newest="$mtime"
  done
  [[ -n "$newest" ]] || return 1
  age=$((now - newest))
  ((age >= 0)) || age=0
  printf '%s' "$age"
}

_heartbeat_mtime() {
  local heartbeat="$1" mtime
  mtime=$(stat -f '%m' "$heartbeat" 2>/dev/null) || true
  if [[ ! "$mtime" =~ ^[0-9]+$ ]]; then
    mtime=$(stat -c '%Y' "$heartbeat" 2>/dev/null) || return 1
  fi
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$mtime"
}

generation_agent_container_id() {
  local generation="$1" project
  project=$(generation_project_name "$generation") || return 1
  docker ps \
    --filter "label=com.docker.compose.project=$project" \
    --filter 'label=com.docker.compose.service=harness' \
    --filter status=running \
    --format '{{.ID}}' | head -n 1
}

current_agent_container_id() {
  local generation container_id
  if [[ -n "${HARNESS_DOCKER_CONTAINER:-}" ]]; then
    docker inspect --format '{{.Id}}' "$HARNESS_DOCKER_CONTAINER"
    return
  fi
  generation=$(read_current_generation) || return 1
  container_id=$(generation_agent_container_id "$generation") || return 1
  [[ -n "$container_id" ]] || return 1
  printf '%s' "$container_id"
}

container_generation() {
  local container="$1" project prefix generation
  project=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$container" 2>/dev/null) || return 1
  prefix="${HARNESS_COMPOSE_PROJECT_NAME:-harness-docker}-g"
  [[ "$project" == "$prefix"* ]] || return 1
  generation="${project#"$prefix"}"
  _valid_generation "$generation" || return 1
  printf '%s' "$generation"
}

list_generations() {
  local current project prefix
  prefix="${HARNESS_COMPOSE_PROJECT_NAME:-harness-docker}-g"
  {
    current=$(read_current_generation 2>/dev/null) && printf '%s\n' "$current"
    docker ps -a --filter 'label=com.docker.compose.project' \
      --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | while IFS= read -r project; do
        [[ "$project" == "$prefix"* ]] && printf '%s\n' "${project#"$prefix"}"
      done
  } | awk 'NF' | sort -u
}

reap_retired_generations() {
  local current generation project session_count rc=0
  current=$(read_current_generation 2>/dev/null) || current=""
  while IFS= read -r generation; do
    [[ -n "$generation" ]] || continue
    [[ "$generation" == "$current" ]] && continue
    session_count=$(generation_session_count "$generation")
    [[ "$session_count" =~ ^[0-9]+$ ]] || session_count=0
    ((session_count == 0)) || continue
    project=$(generation_project_name "$generation") || continue
    if docker compose -p "$project" -f "$HARNESS_DOCKER_ROOT/docker-compose.yml" down; then
      rm -f "$_GENERATIONS_DIR/$generation"/*.hb
      rmdir "$_GENERATIONS_DIR/$generation" 2>/dev/null || true
    else
      rc=1
    fi
  done < <(list_generations)
  return "$rc"
}
