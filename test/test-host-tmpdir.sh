#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/root/config" "$TMP/home" "$TMP/fallback" "$TMP/var/folders/user/T"
cp -R "$ROOT/bin" "$TMP/root/bin"
cp "$ROOT/docker-compose.yml" "$TMP/root/docker-compose.yml"
cp "$ROOT/config/harness-notifier.example" "$TMP/root/config/harness-notifier.example"

cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
printf 'HOST_TMPDIR=%s\n' "$HOST_TMPDIR" >> "$MOCK_LOG"
printf '%q ' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
case "$1" in
  info) exit 0 ;;
  version) echo 1.44; exit 0 ;;
  tag) exit 0 ;;
  compose)
    for ((i=1;i<=$#;i++)); do
      if [[ "${!i}" == -f ]]; then
        j=$((i+1))
        [[ ! -f "${!j}" ]] || sed 's/^/YAML:/' "${!j}" >> "$MOCK_LOG"
      fi
    done
    if [[ "$*" == *' config'* && "$*" != *' -q'* ]]; then
      printf 'services:\n  harness:\n    volumes:\n      - source: /allowed\n'
    fi
    exit 0
    ;;
esac
exit 2
EOF
cat > "$TMP/bin/git" <<'EOF'
#!/bin/bash
[[ "$*" != *describe* ]] || echo test-version
exit 0
EOF
cat > "$TMP/bin/uname" <<'EOF'
#!/bin/bash
[[ "$1" == -s ]] && { echo "$MOCK_OS"; exit 0; }
/bin/uname "$@"
EOF
cat > "$TMP/bin/getconf" <<'EOF'
#!/bin/bash
[[ "$1" == DARWIN_USER_TEMP_DIR ]] || exit 1
[[ "${MOCK_GETCONF_FAIL:-0}" != 1 ]] || exit 1
printf '%s\n' "$MOCK_GETCONF"
EOF
chmod +x "$TMP/bin/docker" "$TMP/bin/git" "$TMP/bin/uname" "$TMP/bin/getconf"
export MOCK_LOG="$TMP/docker.log"
common=(PATH="$TMP/bin:$PATH" HOME="$TMP/home" HOST_HOME="$TMP/home" HOST_USER=tester HOST_UID=1000
  HARNESS_DOCKER_SKIP_UPDATE_CHECK=1 ALLOWED_BIND_MOUNTS=/allowed
  CLAUDE_CONFIG_DIR="$TMP/home/.claude" MOCK_GETCONF="$TMP/var/folders/user/T/")

run_case() {
  local name="$1"; shift
  : > "$MOCK_LOG"
  env -u HOST_TMPDIR "${common[@]}" "$@" "$TMP/root/bin/harness-docker-ctrl" build-image > "$TMP/$name.out" 2>&1
}

run_case darwin TMPDIR="$TMP/fallback" MOCK_OS=Darwin
grep -Fxq "HOST_TMPDIR=$TMP/var/folders/user/T" "$MOCK_LOG"

run_case darwin-fallback TMPDIR="$TMP/fallback" MOCK_OS=Darwin MOCK_GETCONF_FAIL=1
grep -Fxq "HOST_TMPDIR=$TMP/fallback" "$MOCK_LOG"

run_case linux TMPDIR="$TMP/fallback/" MOCK_OS=Linux
grep -Fxq "HOST_TMPDIR=$TMP/fallback" "$MOCK_LOG"

run_case linux-default TMPDIR= MOCK_OS=Linux
grep -Fxq 'HOST_TMPDIR=/tmp' "$MOCK_LOG"

: > "$MOCK_LOG"
env "${common[@]}" TMPDIR="$TMP/fallback" MOCK_OS=Darwin HOST_TMPDIR="$TMP/pre-set/" \
  "$TMP/root/bin/harness-docker-ctrl" build-image > "$TMP/pre-set.out" 2>&1
grep -Fxq "HOST_TMPDIR=$TMP/pre-set" "$MOCK_LOG"

if env "${common[@]}" TMPDIR="$TMP/fallback" MOCK_OS=Linux HOST_TMPDIR=relative \
  "$TMP/root/bin/harness-docker-ctrl" build-image > "$TMP/relative.out" 2>&1; then
  echo 'FAIL: relative HOST_TMPDIR was accepted' >&2
  exit 1
fi
grep -Fq 'HOST_TMPDIR must be an absolute path: relative' "$TMP/relative.out"

cat > "$TMP/root/config/docker-compose.local.yml" <<'EOF'
services:
  harness:
    volumes:
      - ${HOST_TMPDIR}/ActionArtifacts:${HOST_TMPDIR}/ActionArtifacts:ro
x-excludes:
  - ${HOST_TMPDIR}/private
  - $HOST_TMPDIR/token
EOF
mkdir -p "$TMP/var/folders/user/T/private"
touch "$TMP/var/folders/user/T/token"
run_case local-compose TMPDIR="$TMP/fallback" MOCK_OS=Darwin
grep -Fq 'YAML:      - ${HOST_TMPDIR}/ActionArtifacts:${HOST_TMPDIR}/ActionArtifacts:ro' "$MOCK_LOG"
grep -Fq "YAML:      - /dev/null:$TMP/var/folders/user/T/token:ro" "$MOCK_LOG"
grep -Fq "YAML:      - $TMP/var/folders/user/T/private:ro,size=0" "$MOCK_LOG"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  cat > "$TMP/compose-base.yml" <<'EOF'
services:
  harness:
    image: alpine:3
EOF
  HOST_TMPDIR="$TMP/var/folders/user/T" docker compose \
    -f "$TMP/compose-base.yml" -f "$TMP/root/config/docker-compose.local.yml" \
    config > "$TMP/rendered.yml"
  grep -Fq "source: $TMP/var/folders/user/T/ActionArtifacts" "$TMP/rendered.yml"
  grep -Fq "target: $TMP/var/folders/user/T/ActionArtifacts" "$TMP/rendered.yml"
  grep -Fq 'read_only: true' "$TMP/rendered.yml"
fi
echo 'host temporary directory macro: ok'
