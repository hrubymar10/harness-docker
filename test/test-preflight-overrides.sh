#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); LOCAL="$ROOT/config/docker-compose.local.yml"; BACKUP=""
restore() { if [[ -n "$BACKUP" ]]; then mv "$BACKUP" "$LOCAL"; else rm -f "$LOCAL"; fi; rm -rf "$TMP"; }
trap restore EXIT
if [[ -f "$LOCAL" ]]; then BACKUP="$TMP/local.bak"; mv "$LOCAL" "$BACKUP"; fi
mkdir -p "$TMP/bin" "$TMP/tmp"
cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
printf '%q ' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
if [[ "$1" == info ]]; then exit 0; fi
if [[ "$1" == version ]]; then echo "${MOCK_API:-1.44}"; exit 0; fi
if [[ "$1" == compose ]]; then
  for ((i=1;i<=$#;i++)); do if [[ "${!i}" == -f ]]; then j=$((i+1)); [[ -f "${!j}" ]] && sed 's/^/YAML:/' "${!j}" >> "$MOCK_LOG"; fi; done
  if [[ "$*" == *' config'* && "$*" != *' -q'* ]]; then printf 'services:\n  harness:\n    volumes:\n      - source: /allowed\n'; fi
  exit 0
fi
if [[ "$1" == tag ]]; then exit 0; fi
if [[ "$1" == ps ]]; then
  [[ "$*" != *--filter* ]] || echo mock-container
  exit 0
fi
if [[ "$1" == inspect ]]; then echo test-version; exit 0; fi
if [[ "$1" == exec ]]; then
  [[ "$*" != *curl* ]] || echo OK
  exit 0
fi
exit 2
EOF
cat > "$TMP/bin/git" <<'EOF'
#!/bin/bash
if [[ "$*" == *describe* ]]; then echo test-version; fi
exit 0
EOF
cat > "$TMP/bin/date" <<'EOF'
#!/bin/bash
if [[ "$*" == '+%s' ]]; then
  value=$(cat "$MOCK_DATE_COUNTER" 2>/dev/null || echo 1700000000)
  value=$((value + 1))
  echo "$value" > "$MOCK_DATE_COUNTER"
  echo "$value"
else
  /bin/date "$@"
fi
EOF
chmod +x "$TMP/bin/docker" "$TMP/bin/git" "$TMP/bin/date"
export MOCK_LOG="$TMP/docker.log" MOCK_DATE_COUNTER="$TMP/date-counter"
common=(PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmp" HARNESS_DOCKER_SKIP_UPDATE_CHECK=1 ALLOWED_BIND_MOUNTS=/allowed HOST_UID=1000 HOST_USER=tester)

home="$TMP/home"; mkdir -p "$home/projects/secrets"; touch "$home/projects/.env"
cat > "$LOCAL" <<EOF
services:
  harness:
    volumes:
      - $home/projects:$home/projects
x-excludes:
  - $home/projects/.env
  - $home/projects/secrets
EOF
env "${common[@]}" HOME="$home" HOST_HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude-custom" CODEX_HOME="$home/.codex-custom" PI_CODING_AGENT_DIR="$home/.pi/custom" PI_PACKAGE_DIR="$home/.pi/packages" VIBE_HOME="$home/.vibe-custom" OPENCODE_CONFIG_DIR="$home/.opencode-custom" XDG_CONFIG_HOME="$home/.config-custom" XDG_DATA_HOME="$home/.data-custom" DOCKER_GPU=all "$ROOT/bin/harness-docker-ctrl" build-image >/dev/null
for d in "$home/.claude-custom" "$home/.codex-custom" "$home/.pi/custom" "$home/.pi/packages" "$home/.vibe-custom" "$home/.opencode-custom" "$home/.data-custom/opencode"; do [[ -d "$d" ]]; done
grep -Fq 'count: all' "$MOCK_LOG"; grep -Fq "/dev/null:$home/projects/.env:ro" "$MOCK_LOG"; grep -Fq "$home/projects/secrets:ro,size=0" "$MOCK_LOG"
for variable in OPENCODE_CONFIG_DIR XDG_CONFIG_HOME XDG_DATA_HOME; do grep -Fq -- "- $variable" "$MOCK_LOG"; done

default_home="$TMP/default"; mkdir -p "$default_home"
env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u PI_CODING_AGENT_DIR -u PI_PACKAGE_DIR -u VIBE_HOME -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
  "${common[@]}" HOME="$default_home" HOST_HOME="$default_home" "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/default.out" 2>&1
[[ -d "$default_home/.claude" && -d "$default_home/.codex" && -d "$default_home/.pi/agent" && -d "$default_home/.vibe" && -d "$default_home/.config/opencode" && -d "$default_home/.local/share/opencode" ]]
grep -Fq 'CLAUDE_CONFIG_DIR was not set' "$TMP/default.out"

refuse_home="$TMP/refuse"; mkdir -p "$refuse_home"; touch "$refuse_home/.claude.json"
if env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u PI_CODING_AGENT_DIR -u PI_PACKAGE_DIR -u VIBE_HOME -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
  "${common[@]}" HOME="$refuse_home" HOST_HOME="$refuse_home" "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/refuse.out" 2>&1; then exit 1; fi
grep -Fq 'Single-file bind mounts break' "$TMP/refuse.out"

if env "${common[@]}" HOME="$home" HOST_HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" CODEX_HOME=relative "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/absolute.out" 2>&1; then exit 1; fi
grep -Fq 'CODEX_HOME must be an absolute path' "$TMP/absolute.out"

if env "${common[@]}" HOME="$home" HOST_HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" XDG_DATA_HOME=relative "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/xdg-absolute.out" 2>&1; then exit 1; fi
grep -Fq 'XDG_DATA_HOME must be an absolute path' "$TMP/xdg-absolute.out"

: > "$MOCK_LOG"
if env "${common[@]}" HOME="$home" HOST_HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" AWS_AI_PROXY_ENABLED=false AWS_CRED_PROXY_PORT=1 HARNESS_DOCKER_AWS_PROXY_MIGRATION_CHOICE=s "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/aws.out" 2>&1; then exit 1; fi
grep -Fq 'Switch to aws-ai-proxy' "$TMP/aws.out"; if grep -q '^compose ' "$MOCK_LOG"; then exit 1; fi

if env "${common[@]}" HOME="$home" HOST_HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" MOCK_API=1.43 "$ROOT/bin/harness-docker-ctrl" build-image > "$TMP/api.out" 2>&1; then exit 1; fi
grep -Fq 'too old' "$TMP/api.out"

life_root="$TMP/controller-root"
mkdir -p "$life_root/config"
cp -R "$ROOT/bin" "$life_root/bin"
cp "$ROOT/docker-compose.yml" "$life_root/docker-compose.yml"
cp "$ROOT/config/harness-notifier.example" "$life_root/config/harness-notifier.example"
life_home="$TMP/lifecycle-home"; mkdir -p "$life_home"
life_common=("${common[@]}" HOME="$life_home" HOST_HOME="$life_home" CLAUDE_CONFIG_DIR="$life_home/.claude")

run_build_case() {
  local name="$1"; shift
  : > "$MOCK_LOG"
  env "${life_common[@]}" "$life_root/bin/harness-docker-ctrl" "$@" > "$TMP/$name.out"
  grep '^compose .* build ' "$MOCK_LOG" > "$TMP/$name.build"
  grep -Fxq 'tag harness-docker:test-version harness-docker:latest ' "$MOCK_LOG"
}

run_build_case rebuild-one rebuild
grep -Fq -- '--build-arg HARNESS_REFRESH=' "$TMP/rebuild-one.build"
if grep -Fq -- '--no-cache' "$TMP/rebuild-one.build"; then exit 1; fi
first_refresh=$(sed -n 's/.*HARNESS_REFRESH=\([0-9][0-9]*\).*/\1/p' "$TMP/rebuild-one.build")

run_build_case rebuild-two rebuild
second_refresh=$(sed -n 's/.*HARNESS_REFRESH=\([0-9][0-9]*\).*/\1/p' "$TMP/rebuild-two.build")
[[ -n "$first_refresh" && -n "$second_refresh" && "$first_refresh" != "$second_refresh" ]]

run_build_case rebuild-no-cache rebuild --no-cache
grep -Fq -- '--no-cache' "$TMP/rebuild-no-cache.build"
if grep -Fq -- 'HARNESS_REFRESH=' "$TMP/rebuild-no-cache.build"; then exit 1; fi

rm -f "$life_root/config/.current-generation"
run_build_case start-default start
if grep -Eq -- '--no-cache|HARNESS_REFRESH=' "$TMP/start-default.build"; then exit 1; fi

rm -f "$life_root/config/.current-generation"
run_build_case start-no-cache start --no-cache
grep -Fq -- '--no-cache' "$TMP/start-no-cache.build"
if grep -Fq -- 'HARNESS_REFRESH=' "$TMP/start-no-cache.build"; then exit 1; fi

run_build_case image-default build-image
if grep -Eq -- '--no-cache|HARNESS_REFRESH=' "$TMP/image-default.build"; then exit 1; fi

run_build_case image-no-cache build-image --no-cache
grep -Fq -- '--no-cache' "$TMP/image-no-cache.build"
if grep -Fq -- 'HARNESS_REFRESH=' "$TMP/image-no-cache.build"; then exit 1; fi

if env "${life_common[@]}" "$life_root/bin/harness-docker-ctrl" rebuild --bogus > "$TMP/bogus.out" 2>&1; then exit 1; fi
grep -Fq 'usage: harness-docker-ctrl rebuild [--no-cache]' "$TMP/bogus.out"
echo 'controller preflight overrides: ok'
