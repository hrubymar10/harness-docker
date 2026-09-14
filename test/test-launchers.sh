#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); POINTER="$ROOT/config/.current-generation"; POINTER_BACKUP=""
ENV_FILE="$ROOT/config/.env"; ENV_BACKUP=""
restore() {
  if [[ -n "$POINTER_BACKUP" ]]; then cp "$POINTER_BACKUP" "$POINTER"; else rm -f "$POINTER"; fi
  if [[ -n "$ENV_BACKUP" ]]; then mv "$ENV_BACKUP" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
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
  inspect) [[ "$*" == *State.Status* ]] && echo running || echo "$MOUNT" ;;
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
  [[ "${HARNESS_LAUNCH_FLAGS[*]}" == "$expected_flags" ]]
  [[ "${#HARNESS_STATE_DIR_ENVS[@]}" == "${#HARNESS_STATE_DIR_SUFFIXES[@]}" ]]
  if [[ "$harness" == opencode ]]; then
    [[ "${HARNESS_STATE_DIR_ENVS[*]}" == 'OPENCODE_CONFIG_DIR XDG_DATA_HOME' ]]
    [[ "${HARNESS_STATE_DIR_SUFFIXES[*]}" == ' opencode' ]]
  fi
  [[ "$(HARNESS_DOCKER_ROOT="$ROOT" bash -c 'source "$HARNESS_DOCKER_ROOT/bin/lib/harness.sh"; harness_from_launcher "$0"' "$ROOT/bin/$harness-docker")" == "$harness" ]]
  grep -q '^harness-mock$' "$TMP/out"
  grep -Eq "exec -i .*${HARNESS_SESSION_ENV}=.* -e HARNESS_DOCKER_SESSION_PID_DIR=/tmp -u tester -w .*/work/project cid-pinned ${HARNESS_SESSION_WRAPPER}" "$LOG"
  for flag in "${HARNESS_LAUNCH_FLAGS[@]}"; do grep -Fq -- "$flag" "$LOG"; done
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
