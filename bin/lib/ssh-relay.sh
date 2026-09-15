# shellcheck shell=bash
# Host-side socat relay that exposes the local SSH agent socket to the sandbox
# on 127.0.0.1:$SSH_RELAY_PORT. Shared by the controller and the launchers.
# The relay runs detached from the caller's terminal session and records its
# own PID once it holds the port, so a spawn that lost the port to a
# concurrent caller never overwrites the record of the one that won.

_SSH_RELAY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F _spawn_detached >/dev/null; then
  # shellcheck source=bin/lib/session-cleanup.sh
  source "$_SSH_RELAY_LIB_DIR/session-cleanup.sh"
fi

ssh_relay_port() { printf '%s' "${SSH_RELAY_PORT:-19922}"; }
ssh_relay_pid_file() { printf '%s' "${SSH_RELAY_PID_FILE:-$HOME/.harness-docker-ssh-relay.pid}"; }

_ssh_relay_command() { ps -p "$1" -o command= 2>/dev/null; }

# A live process whose command line is an agent relay, on any port: the PID
# file is ours, so a relay it names is ours even after the port changed.
_ssh_relay_is_relay() {
  local command
  [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null || return 1
  command=$(_ssh_relay_command "$1")
  [[ "$command" == *"TCP-LISTEN:"* && "$command" == *"UNIX-CONNECT:"* ]]
}

# A relay that serves the current port and still reaches its agent socket; the
# UNIX-CONNECT address is the last argument.
_ssh_relay_usable() {
  local command agent_socket
  command=$(_ssh_relay_command "$1")
  agent_socket="${command##*UNIX-CONNECT:}"
  [[ "$command" == *"TCP-LISTEN:$(ssh_relay_port),"* \
    && "$agent_socket" == "$SSH_AUTH_SOCK" && -S "$agent_socket" ]]
}

_ssh_relay_port_served() {
  command -v lsof >/dev/null && lsof -nP -iTCP:"$(ssh_relay_port)" -sTCP:LISTEN >/dev/null 2>&1
}

_ssh_relay_wait_exit() {
  local i
  for ((i = 0; i < 40; i++)); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.05
  done
  return 1
}

# start_ssh_relay [--quiet]: --quiet suppresses the port-reuse notice, which a
# launcher would otherwise repeat on every session while another process
# serves the port.
start_ssh_relay() {
  local pid_file port quiet=false pid
  [[ "${1:-}" != --quiet ]] || quiet=true
  [[ -S "${SSH_AUTH_SOCK:-}" ]] || return 0
  pid_file=$(ssh_relay_pid_file); port=$(ssh_relay_port)
  # The recorded PID may be stale while a detached successor starts.
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if _ssh_relay_is_relay "$pid"; then
    _ssh_relay_usable "$pid" && return 0
    kill "$pid" 2>/dev/null
    _ssh_relay_wait_exit "$pid" || { echo "Warning: relay $pid did not stop; SSH relay not restarted." >&2; return; }
  fi
  command -v socat >/dev/null || { echo 'Warning: socat not found; SSH relay disabled.' >&2; return; }
  if _ssh_relay_port_served; then
    $quiet || echo "SSH relay port $port is already served; reusing it." >&2
    return 0
  fi
  # shellcheck disable=SC2016
  _spawn_detached '
    socat TCP-LISTEN:"$2",fork,reuseaddr,bind=127.0.0.1 UNIX-CONNECT:"$3" &
    relay=$!
    temporary="$1.$relay"
    trap '\''rm -f "$temporary"'\'' EXIT
    sleep 0.3
    kill -0 "$relay" 2>/dev/null || exit 0
    printf "%s\n" "$relay" > "$temporary"
    mv "$temporary" "$1"
  ' "$pid_file" "$port" "$SSH_AUTH_SOCK"
}

stop_ssh_relay() {
  local pid_file pid
  pid_file=$(ssh_relay_pid_file)
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if _ssh_relay_is_relay "$pid"; then kill "$pid" 2>/dev/null; fi
  rm -f "$pid_file"
}
