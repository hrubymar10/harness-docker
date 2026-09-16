# shellcheck shell=bash

_LAUNCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DOCKER_ROOT="$(cd "$_LAUNCH_LIB_DIR/../.." && pwd)"

# shellcheck source=bin/lib/harness.sh
source "$_LAUNCH_LIB_DIR/harness.sh"
# shellcheck source=bin/lib/generations.sh
source "$_LAUNCH_LIB_DIR/generations.sh"
# shellcheck source=bin/lib/ssh-relay.sh
source "$_LAUNCH_LIB_DIR/ssh-relay.sh"

_load_harness_env() {
  local env_file="$HARNESS_DOCKER_ROOT/config/.env" line key value
  [[ -f "$env_file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "$value" == '"'*'"' ]]; then value="${value#\"}"; value="${value%\"}"
    elif [[ "$value" == "'"*"'" ]]; then value="${value#\'}"; value="${value%\'}"; fi
    [[ -n "${!key:-}" ]] || export "$key=$value"
  done < "$env_file"
}

# <HARNESS>_LAUNCH_FLAGS replaces the launcher's built-in flags; an empty
# value clears them.
_apply_launch_flags_override() {
  local variable
  variable="$(printf '%s' "$HARNESS" | tr '[:lower:]' '[:upper:]')_LAUNCH_FLAGS"
  [[ -n "${!variable+x}" ]] || return 0
  read -ra HARNESS_LAUNCH_FLAGS <<< "${!variable}"
}

_launcher_script_path() {
  local path="$1" link_dir
  while [[ -L "$path" ]]; do
    link_dir="$(cd "$(dirname "$path")" && pwd)"
    path="$(readlink "$path")"
    [[ "$path" == /* ]] || path="$link_dir/$path"
  done
  printf '%s' "$path"
}

_die() {
  echo "Error: $1" >&2
  return 1
}

harness_main() {
  local script_path derived_harness container_id generation status workdir mounts mounted source_path
  local docker_user session_id exit_code launch_flags_variable launch_flags_was_set
  local launch_flags_host_value relay_port
  local -a docker_flags launch_flags

  script_path=$(_launcher_script_path "$0")
  derived_harness=$(harness_from_launcher "$script_path") || {
    _die "cannot determine harness from '$0'."
    return 1
  }
  HARNESS="${HARNESS:-$derived_harness}"
  if [[ "$HARNESS" != "$derived_harness" ]]; then
    _die "launcher '$derived_harness' cannot run harness '$HARNESS'."
    return 1
  fi
  load_harness_spec "$HARNESS"
  launch_flags_variable="$(printf '%s' "$HARNESS" | tr '[:lower:]' '[:upper:]')_LAUNCH_FLAGS"
  launch_flags_was_set="${!launch_flags_variable+x}"
  launch_flags_host_value="${!launch_flags_variable-}"
  _load_harness_env
  if [[ -n "$launch_flags_was_set" ]]; then
    export "$launch_flags_variable=$launch_flags_host_value"
  fi
  _apply_launch_flags_override

  docker info >/dev/null 2>&1 || {
    _die "Docker is not running."
    return 1
  }
  # HARNESS_DOCKER_CONTAINER overrides generation lookup; it is still resolved
  # once to an immutable ID. HARNESS_DOCKER_USER overrides the exec user only.
  container_id=$(current_agent_container_id) || {
    _die "Harness is not started. Run: bin/harness-docker-ctrl start"
    return 1
  }
  status=$(docker inspect --format '{{.State.Status}}' "$container_id" 2>/dev/null) \
    || {
      _die "Harness container does not exist. Run: bin/harness-docker-ctrl start"
      return 1
    }
  if [[ "$status" != running ]]; then
    _die "Harness container is $status. Run: bin/harness-docker-ctrl start"
    return 1
  fi
  # The container dials the port it was started with, so the heal uses that
  # one rather than the current config/.env value.
  if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
    relay_port=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_id" | sed -n 's/^SSH_RELAY_PORT=//p')
    if [[ -n "$relay_port" ]]; then SSH_RELAY_PORT="$relay_port" start_ssh_relay --quiet; fi
  fi

  workdir=$(pwd)
  mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}' "$container_id")
  mounted=false
  for source_path in $mounts; do
    if [[ "$workdir" == "$source_path" || "$workdir" == "$source_path/"* ]]; then
      mounted=true
      break
    fi
  done
  if ! $mounted; then
    _die "Directory '$workdir' is not mounted in the harness container. Add it to config/docker-compose.local.yml."
    return 1
  fi

  docker_user="${HARNESS_DOCKER_USER:-${HOST_USER:-$(whoami)}}"
  # shellcheck source=bin/lib/session-cleanup.sh
  source "$_LAUNCH_LIB_DIR/session-cleanup.sh"
  reap_stale_sessions "$container_id" "$docker_user"

  session_id="$$-$RANDOM-$(date +%s)"
  generation=$(container_generation "$container_id") || {
    _die "Harness container is not part of a managed generation."
    return 1
  }
  start_session_watchdog "$container_id" "$session_id" "$$" "$generation" "$docker_user"

  docker_flags=(-i)
  launch_flags=(${HARNESS_LAUNCH_FLAGS[@]+"${HARNESS_LAUNCH_FLAGS[@]}"})
  if [[ "$HARNESS" == claude && "${HARNESS_LAUNCH_MODE:-}" == claude-vscode ]]; then
    (($# > 0)) && shift
    launch_flags=()
  elif [[ -t 0 ]]; then
    docker_flags+=(-t)
  fi

  set +e
  docker exec "${docker_flags[@]}" \
    -e "$HARNESS_SESSION_ENV=$session_id" \
    -e "HARNESS_DOCKER_SESSION_PID_DIR=${HARNESS_DOCKER_SESSION_PID_DIR:-/tmp}" \
    -u "$docker_user" -w "$workdir" "$container_id" \
    "$HARNESS_SESSION_WRAPPER" ${launch_flags[@]+"${launch_flags[@]}"} "$@"
  exit_code=$?
  set -e

  run_session_cleanup "$container_id" "$session_id" "$generation" "$docker_user"
  return "$exit_code"
}
