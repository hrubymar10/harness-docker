#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/harness-update.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/seed/bin/lib" "$TEST_ROOT/seed/config" "$TEST_ROOT/home"
TEST_GIT=$(command -v git)
[[ ! -x /usr/libexec/git-real/git ]] || TEST_GIT=/usr/libexec/git-real/git
mkdir -p "$TEST_ROOT/git-exec"
cat > "$TEST_ROOT/git-exec/git-upload-pack" <<EOF
#!/bin/sh
exec "$TEST_GIT" upload-pack "\$@"
EOF
chmod +x "$TEST_ROOT/git-exec/git-upload-pack"
cp "$ROOT/bin/harness-docker-ctrl" "$TEST_ROOT/seed/bin/"
cp "$ROOT/bin/lib/"{harness,generations,session-cleanup,ssh-relay}.sh "$TEST_ROOT/seed/bin/lib/"
printf 'base\n' > "$TEST_ROOT/seed/state"

"$TEST_GIT" -C "$TEST_ROOT/seed" init -q -b main
"$TEST_GIT" -C "$TEST_ROOT/seed" config user.name Test
"$TEST_GIT" -C "$TEST_ROOT/seed" config user.email test@example.invalid
"$TEST_GIT" -C "$TEST_ROOT/seed" add .
"$TEST_GIT" -C "$TEST_ROOT/seed" commit -q -m base
"$TEST_GIT" clone -q --bare --upload-pack="$TEST_ROOT/git-exec/git-upload-pack" "$TEST_ROOT/seed" "$TEST_ROOT/remote.git"
"$TEST_GIT" clone -q --upload-pack="$TEST_ROOT/git-exec/git-upload-pack" "$TEST_ROOT/remote.git" "$TEST_ROOT/local"
"$TEST_GIT" clone -q --upload-pack="$TEST_ROOT/git-exec/git-upload-pack" "$TEST_ROOT/remote.git" "$TEST_ROOT/publisher"
"$TEST_GIT" -C "$TEST_ROOT/local" config user.name Test
"$TEST_GIT" -C "$TEST_ROOT/local" config user.email test@example.invalid
"$TEST_GIT" -C "$TEST_ROOT/publisher" config user.name Test
"$TEST_GIT" -C "$TEST_ROOT/publisher" config user.email test@example.invalid

CTRL="$TEST_ROOT/local/bin/harness-docker-ctrl"
REMOTE="$TEST_ROOT/remote.git"
COMMON_ENV=(HOME="$TEST_ROOT/home" GIT_EXEC_PATH="$TEST_ROOT/git-exec" HARNESS_DOCKER_UPDATE_REMOTE="$REMOTE" HARNESS_DOCKER_UPDATE_TIMEOUT_SECONDS=2)

run_ctrl() { env "${COMMON_ENV[@]}" "$CTRL" "$@"; }
assert_contains() { grep -F "$2" "$1" >/dev/null || { echo "missing '$2' in $1" >&2; exit 1; }; }

run_ctrl update --check > "$TEST_ROOT/current.out"
assert_contains "$TEST_ROOT/current.out" 'harness-docker is current at'
run_ctrl beeper-stop > "$TEST_ROOT/passive-current.out" 2>&1
[[ ! -s "$TEST_ROOT/passive-current.out" ]]

printf 'remote-one\n' >> "$TEST_ROOT/publisher/state"
"$TEST_GIT" -C "$TEST_ROOT/publisher" add state
"$TEST_GIT" -C "$TEST_ROOT/publisher" commit -q -m remote-one
"$TEST_GIT" -C "$TEST_ROOT/publisher" push -q --receive-pack="$TEST_GIT receive-pack" origin main
run_ctrl update --check > "$TEST_ROOT/behind.out"
assert_contains "$TEST_ROOT/behind.out" 'harness-docker update available:'
run_ctrl beeper-stop > "$TEST_ROOT/passive-behind.out" 2>&1
assert_contains "$TEST_ROOT/passive-behind.out" 'continuing without update'

cat > "$TEST_ROOT/pty-run.py" <<'PY'
import os, pty, sys
status = pty.spawn(sys.argv[1:])
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
config_before=$(git -C "$TEST_ROOT/local" hash-object .git/config)
printf '\n' | env "${COMMON_ENV[@]}" python3 "$TEST_ROOT/pty-run.py" "$CTRL" beeper-stop > "$TEST_ROOT/interactive.out" 2>&1
assert_contains "$TEST_ROOT/interactive.out" 'harness-docker update available. update now? (Y/n)'
assert_contains "$TEST_ROOT/interactive.out" 'Updated harness-docker from'
assert_eq_remote=$(git --git-dir="$REMOTE" rev-parse refs/heads/main)
[[ "$(git -C "$TEST_ROOT/local" rev-parse HEAD)" == "$assert_eq_remote" ]]
[[ "$(git -C "$TEST_ROOT/local" hash-object .git/config)" == "$config_before" ]]

printf 'remote-explicit\n' >> "$TEST_ROOT/publisher/state"
"$TEST_GIT" -C "$TEST_ROOT/publisher" add state
"$TEST_GIT" -C "$TEST_ROOT/publisher" commit -q -m remote-explicit
"$TEST_GIT" -C "$TEST_ROOT/publisher" push -q --receive-pack="$TEST_GIT receive-pack" origin main
run_ctrl update > "$TEST_ROOT/explicit-update.out"
assert_contains "$TEST_ROOT/explicit-update.out" 'Updated harness-docker from'
assert_eq_remote=$(git --git-dir="$REMOTE" rev-parse refs/heads/main)
[[ "$(git -C "$TEST_ROOT/local" rev-parse HEAD)" == "$assert_eq_remote" ]]
if run_ctrl update --yes > "$TEST_ROOT/no-yes.out" 2>&1; then exit 1; fi
assert_contains "$TEST_ROOT/no-yes.out" 'usage: harness-docker-ctrl update [--check]'

printf 'dirty\n' >> "$TEST_ROOT/local/state"
run_ctrl update --check > "$TEST_ROOT/dirty.out"
assert_contains "$TEST_ROOT/dirty.out" 'dirty checkout; check skipped'
run_ctrl beeper-stop > "$TEST_ROOT/passive-dirty.out" 2>&1
assert_contains "$TEST_ROOT/passive-dirty.out" 'update check skipped: checkout is dirty'
"$TEST_GIT" -C "$TEST_ROOT/local" checkout -q -- state

"$TEST_GIT" -C "$TEST_ROOT/local" switch -q -c feature
run_ctrl update --check > "$TEST_ROOT/non-default.out"
assert_contains "$TEST_ROOT/non-default.out" "non-default branch 'feature'"
run_ctrl beeper-stop > "$TEST_ROOT/passive-non-default.out" 2>&1
assert_contains "$TEST_ROOT/passive-non-default.out" "not default branch 'main'"
if run_ctrl update > "$TEST_ROOT/non-default-update.out" 2>&1; then exit 1; fi
assert_contains "$TEST_ROOT/non-default-update.out" 'update refused'
"$TEST_GIT" -C "$TEST_ROOT/local" switch -q main

env HOME="$TEST_ROOT/home" HARNESS_DOCKER_UPDATE_REMOTE="$TEST_ROOT/missing.git" HARNESS_DOCKER_UPDATE_TIMEOUT_SECONDS=1 \
  "$CTRL" update --check > "$TEST_ROOT/unreachable.out"
assert_contains "$TEST_ROOT/unreachable.out" 'is unreachable'
env HOME="$TEST_ROOT/home" HARNESS_DOCKER_UPDATE_REMOTE="$TEST_ROOT/missing.git" HARNESS_DOCKER_UPDATE_TIMEOUT_SECONDS=1 \
  "$CTRL" beeper-stop > "$TEST_ROOT/passive-unreachable.out" 2>&1
[[ ! -s "$TEST_ROOT/passive-unreachable.out" ]]

# Diverge the local default branch and remote, then accept the passive offer.
# The ff-only failure must preserve the exact local branch and continue.
printf 'local-divergence\n' >> "$TEST_ROOT/local/state"
"$TEST_GIT" -C "$TEST_ROOT/local" add state
"$TEST_GIT" -C "$TEST_ROOT/local" commit -q -m local-divergence
local_before=$(git -C "$TEST_ROOT/local" rev-parse HEAD)
printf 'remote-divergence\n' >> "$TEST_ROOT/publisher/state"
"$TEST_GIT" -C "$TEST_ROOT/publisher" add state
"$TEST_GIT" -C "$TEST_ROOT/publisher" commit -q -m remote-divergence
"$TEST_GIT" -C "$TEST_ROOT/publisher" push -q --receive-pack="$TEST_GIT receive-pack" origin main
printf '\n' | env "${COMMON_ENV[@]}" python3 "$TEST_ROOT/pty-run.py" "$CTRL" beeper-stop > "$TEST_ROOT/rollback.out" 2>&1
assert_contains "$TEST_ROOT/rollback.out" 'automatic update failed'
[[ "$(git -C "$TEST_ROOT/local" rev-parse HEAD)" == "$local_before" ]]
[[ "$(git -C "$TEST_ROOT/local" symbolic-ref --short HEAD)" == main ]]

echo 'default-branch update system: ok'
