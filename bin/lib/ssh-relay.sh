# shellcheck shell=bash
# Host-side socat relay that exposes the local SSH agent socket to the sandbox
# on 127.0.0.1:$SSH_RELAY_PORT. The controller starts and stops the relay with
# the shared stack lifecycle.

ssh_relay_port() { printf '%s' "${SSH_RELAY_PORT:-19922}"; }
ssh_relay_pid_file() { printf '%s' "${SSH_RELAY_PID_FILE:-$HOME/.harness-docker-ssh-relay.pid}"; }

ssh_relay_healthy() {
  local pid_file pid
  pid_file=$(ssh_relay_pid_file)
  [[ -f "$pid_file" ]] || return 1
  pid=$(cat "$pid_file")
  kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q "TCP-LISTEN:$(ssh_relay_port)"
}

start_ssh_relay() {
  local pid_file port
  [[ -S "${SSH_AUTH_SOCK:-}" ]] || return 0
  ssh_relay_healthy && return 0
  pid_file=$(ssh_relay_pid_file); port=$(ssh_relay_port)
  rm -f "$pid_file"
  command -v socat >/dev/null || { echo 'Warning: socat not found; SSH relay disabled.' >&2; return; }
  if command -v lsof >/dev/null && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "SSH relay port $port is already served; reusing it." >&2
    return 0
  fi
  socat TCP-LISTEN:"$port",fork,reuseaddr,bind=127.0.0.1 UNIX-CONNECT:"$SSH_AUTH_SOCK" &
  echo "$!" > "$pid_file"
}

stop_ssh_relay() {
  local pid_file pid command_line
  pid_file=$(ssh_relay_pid_file)
  if [[ -f "$pid_file" ]]; then
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
      if [[ "$command_line" == *TCP-LISTEN:*UNIX-CONNECT:* ]]; then kill "$pid"; fi
    fi
  fi
  rm -f "$pid_file"
}
