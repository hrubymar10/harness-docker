# shellcheck shell=bash

if [[ -z "${HARNESS_DOCKER_ROOT:-}" ]]; then
  HARNESS_DOCKER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

_GENERATION_POINTER="$HARNESS_DOCKER_ROOT/config/.current-generation"
_RETIRED_GENERATIONS_DIR="$HARNESS_DOCKER_ROOT/config/.retired-generations"

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

generation_is_retired() {
  local generation="$1"
  _valid_generation "$generation" || return 1
  [[ -f "$_RETIRED_GENERATIONS_DIR/$generation" ]]
}

generation_session_count() {
  _generation_session_count "$1"
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

mark_generation_retired() {
  local generation="$1" marker tmp
  _valid_generation "$generation" || return 1
  mkdir -p "$_RETIRED_GENERATIONS_DIR"
  marker="$_RETIRED_GENERATIONS_DIR/$generation"
  tmp=$(mktemp "${marker}.tmp.XXXXXX")
  if ! printf '%s\n' "$generation" > "$tmp" || ! mv -f "$tmp" "$marker"; then
    rm -f "$tmp"
    return 1
  fi
}

list_generations() {
  local current marker project prefix
  prefix="${HARNESS_COMPOSE_PROJECT_NAME:-harness-docker}-g"
  {
    current=$(read_current_generation 2>/dev/null) && printf '%s\n' "$current"
    for marker in "$_RETIRED_GENERATIONS_DIR"/*; do
      [[ -f "$marker" ]] && basename "$marker"
    done
    docker ps -a --filter 'label=com.docker.compose.project' \
      --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | while IFS= read -r project; do
        [[ "$project" == "$prefix"* ]] && printf '%s\n' "${project#"$prefix"}"
      done
  } | awk 'NF' | sort -u
}

_generation_session_count() {
  local generation="$1" container_id count
  container_id=$(generation_agent_container_id "$generation") || true
  if [[ -z "$container_id" ]]; then
    printf '0'
    return
  fi
  count=$(docker exec "$container_id" sh -c '
    set -- /tmp/*-session-*.pid
    [ -e "$1" ] || { echo 0; exit 0; }
    echo "$#"
  ' 2>/dev/null) || count=0
  printf '%s' "$count"
}

reap_retired_generations() {
  local current marker generation project session_count
  current=$(read_current_generation 2>/dev/null) || current=""
  for marker in "$_RETIRED_GENERATIONS_DIR"/*; do
    [[ -f "$marker" ]] || continue
    generation=$(basename "$marker")
    _valid_generation "$generation" || continue
    [[ "$generation" == "$current" ]] && continue
    session_count=$(_generation_session_count "$generation")
    [[ "$session_count" =~ ^[0-9]+$ ]] || session_count=0
    ((session_count == 0)) || continue
    project=$(generation_project_name "$generation") || continue
    docker compose -p "$project" -f "$HARNESS_DOCKER_ROOT/docker-compose.yml" down
    rm -f "$marker"
  done
}
