# shellcheck shell=bash
# Table fields are consumed by the shared launcher after this file is sourced.
# shellcheck disable=SC2034

harness_version() {
  local root="${HARNESS_DOCKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  git -C "$root" describe --tags --always --dirty
}

harness_from_launcher() {
  local launcher
  launcher=$(basename "$1")
  launcher=${launcher%-vscode-wrapper}
  launcher=${launcher%-docker}
  case "$launcher" in
    claude|codex|pi|vibe|opencode) printf '%s' "$launcher" ;;
    *) return 1 ;;
  esac
}

load_harness_spec() {
  HARNESS="${1:-}"
  case "$HARNESS" in
    claude)
      HARNESS_BINARY=claude
      HARNESS_SESSION_ENV=CLAUDE_SESSION_ID
      HARNESS_SESSION_WRAPPER=claude-session
      HARNESS_LAUNCH_FLAGS=(--dangerously-skip-permissions)
      HARNESS_NOTIFIER=claude-notifier
      HARNESS_STATE_DIR_ENVS=(CLAUDE_CONFIG_DIR)
      HARNESS_STATE_DIR_SUFFIXES=('')
      ;;
    codex)
      HARNESS_BINARY=codex
      HARNESS_SESSION_ENV=CODEX_SESSION_ID
      HARNESS_SESSION_WRAPPER=codex-session
      HARNESS_LAUNCH_FLAGS=(--dangerously-bypass-approvals-and-sandbox)
      HARNESS_NOTIFIER=codex-notifier
      HARNESS_STATE_DIR_ENVS=(CODEX_HOME)
      HARNESS_STATE_DIR_SUFFIXES=('')
      ;;
    pi)
      HARNESS_BINARY=pi
      HARNESS_SESSION_ENV=PI_SESSION_ID
      HARNESS_SESSION_WRAPPER=pi-session
      HARNESS_LAUNCH_FLAGS=()
      HARNESS_NOTIFIER=pi-notifier
      HARNESS_STATE_DIR_ENVS=(PI_CODING_AGENT_DIR)
      HARNESS_STATE_DIR_SUFFIXES=('')
      ;;
    vibe)
      HARNESS_BINARY=vibe
      HARNESS_SESSION_ENV=VIBE_SESSION_ID
      HARNESS_SESSION_WRAPPER=vibe-session
      HARNESS_LAUNCH_FLAGS=(--yolo)
      HARNESS_NOTIFIER=vibe-notifier
      HARNESS_STATE_DIR_ENVS=(VIBE_HOME)
      HARNESS_STATE_DIR_SUFFIXES=('')
      ;;
    opencode)
      HARNESS_BINARY=opencode
      HARNESS_SESSION_ENV=OPENCODE_SESSION_ID
      HARNESS_SESSION_WRAPPER=opencode-session
      HARNESS_LAUNCH_FLAGS=(--auto)
      HARNESS_NOTIFIER=opencode-notifier
      HARNESS_STATE_DIR_ENVS=(OPENCODE_CONFIG_DIR XDG_DATA_HOME)
      HARNESS_STATE_DIR_SUFFIXES=('' opencode)
      ;;
    *)
      echo "Error: unsupported harness '$HARNESS'." >&2
      return 1
      ;;
  esac
}
