#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
home="$TMP/home"; mkdir -p "$home"/{.claude,.codex,.pi/agent,.vibe,.config/opencode,.local/share/opencode,go/pkg}
common=(PATH="$PATH" HOME="$home" DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}" HOST_UID=1000 HOST_USER=tester HOST_HOME="$home" GO_VERSION=go1.26.0 GOPATH="$home/go" CLAUDE_CONFIG_DIR_HOST="$home/.claude" CODEX_HOME_HOST="$home/.codex" PI_CODING_AGENT_DIR_HOST="$home/.pi/agent" VIBE_HOME_HOST="$home/.vibe" OPENCODE_CONFIG_DIR_HOST="$home/.config/opencode" OPENCODE_DATA_DIR_HOST="$home/.local/share/opencode")
grep -Fq 'ENV HOST_UID="${HOST_UID}" HOST_USER="${HOST_USER}" HOST_HOME="${HOST_HOME}"' Dockerfile
for files in '-f docker-compose.yml' '-f docker-compose.yml -f config/docker-compose.local.example.yml'; do
  read -r -a compose_files <<< "$files"
  env -i "${common[@]}" docker compose --env-file /dev/null "${compose_files[@]}" config > "$TMP/out" 2> "$TMP/err"
  [[ ! -s "$TMP/err" ]]
  [[ "$(env -i "${common[@]}" docker compose --env-file /dev/null "${compose_files[@]}" config --services | sort | paste -sd, -)" == filter-proxy,harness,socket-proxy ]]
  if grep -q 'container_name:' "$TMP/out"; then exit 1; fi
  sed -n '/^  filter-proxy:/,/^  harness:/p' "$TMP/out" | grep -q '^    read_only: true$'
  sed -n '/^  filter-proxy:/,/^  harness:/p' "$TMP/out" | grep -q '^    tmpfs:$'
  sed -n '/^  socket-proxy:/,/^networks:/p' "$TMP/out" | grep -q '^    read_only: true$'
  sed -n '/^  socket-proxy:/,/^networks:/p' "$TMP/out" | grep -q '^    tmpfs:$'
  for path in "$home/.claude" "$home/.codex" "$home/.pi/agent" "$home/.vibe" "$home/.config/opencode" "$home/.local/share/opencode" "$home/go/pkg" "$ROOT/gpg-keys" "$ROOT/config/harness-notifier" "$ROOT/config/custom-bin"; do grep -Fq "source: $path" "$TMP/out"; done
  for key in DOCKER_HOST GITHUB_TOKEN GITLAB_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY MISTRAL_API_KEY CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR VIBE_HOME AWS_AI_PROXY_ENABLED; do grep -q "^      $key:" "$TMP/out"; done
  for key in OPENCODE_CONFIG_DIR XDG_CONFIG_HOME XDG_DATA_HOME; do if grep -q "^      $key:" "$TMP/out"; then exit 1; fi; done
  for arg in HOST_UID HOST_USER HOST_HOME GO_VERSION CONTAINER_SHELL EXTRA_PACKAGES EXTRA_GO_PACKAGES EXTRA_NPM_PACKAGES CC_VERSION CODEX_VERSION PI_VERSION VIBE_VERSION OPENCODE_VERSION VERSION; do grep -q "^        $arg:" "$TMP/out"; done
done
echo 'compose config: ok'
