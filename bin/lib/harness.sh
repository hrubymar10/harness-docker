# shellcheck shell=bash
# Table fields are consumed by the shared launcher after this file is sourced.
# shellcheck disable=SC2034

harness_from_launcher() {
  local launcher
  launcher=$(basename "$1")
  launcher=${launcher%-vscode-wrapper}
  launcher=${launcher%-docker}
  case "$launcher" in
    claude|codex|pi|vibe) printf '%s' "$launcher" ;;
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
      HARNESS_CONFIG_DIR_ENV=CLAUDE_CONFIG_DIR
      ;;
    codex)
      HARNESS_BINARY=codex
      HARNESS_SESSION_ENV=CODEX_SESSION_ID
      HARNESS_SESSION_WRAPPER=codex-session
      HARNESS_LAUNCH_FLAGS=(--dangerously-bypass-approvals-and-sandbox)
      HARNESS_NOTIFIER=codex-notifier
      HARNESS_CONFIG_DIR_ENV=CODEX_HOME
      ;;
    pi)
      HARNESS_BINARY=pi
      HARNESS_SESSION_ENV=PI_SESSION_ID
      HARNESS_SESSION_WRAPPER=pi-session
      HARNESS_LAUNCH_FLAGS=()
      HARNESS_NOTIFIER=pi-notifier
      HARNESS_CONFIG_DIR_ENV=PI_CODING_AGENT_DIR
      ;;
    vibe)
      HARNESS_BINARY=vibe
      HARNESS_SESSION_ENV=VIBE_SESSION_ID
      HARNESS_SESSION_WRAPPER=vibe-session
      HARNESS_LAUNCH_FLAGS=(--yolo)
      HARNESS_NOTIFIER=vibe-notifier
      HARNESS_CONFIG_DIR_ENV=VIBE_HOME
      ;;
    *)
      echo "Error: unsupported harness '$HARNESS'." >&2
      return 1
      ;;
  esac
}
